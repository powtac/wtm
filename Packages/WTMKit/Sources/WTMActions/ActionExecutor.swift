import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public enum ActionExecutorError: Error, Equatable, Sendable {
  case noSelection
  case adapterUnavailable(ProviderID)
  case planNotActive
  case planExpired
  case planConflict
  case irreversibleConfirmationRequired
  case inventoryChanged
  case sourceUnavailable(ScanSource.ID)
  case targetInUse
  case targetRevalidationFailed
  case providerRevalidationFailed(ProviderID)
}

/// Serializes Phase 2 cleanup, consumes every plan once, and revalidates before mutation.
public actor ActionExecutor {
  public nonisolated let supportedProviderIDs: Set<ProviderID>
  private let registry: StorageActionAdapterRegistry
  private let trashMover: any TrashMoving
  private let auditStore: any ActionAuditStoring
  private let targetPolicy: DeletionTargetPolicy
  private let openFileUsageChecker: any OpenFileUsageChecking
  private let planLifetime: TimeInterval
  private let now: @Sendable () -> Date
  private var activePlan: DeletionPlan?

  public init(
    registry: StorageActionAdapterRegistry,
    trashMover: any TrashMoving,
    auditStore: any ActionAuditStoring,
    targetPolicy: DeletionTargetPolicy = DeletionTargetPolicy(),
    openFileUsageChecker: any OpenFileUsageChecking = SystemOpenFileUsageChecker(),
    planLifetime: TimeInterval = 300,
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    supportedProviderIDs = registry.providerIDs
    self.registry = registry
    self.trashMover = trashMover
    self.auditStore = auditStore
    self.targetPolicy = targetPolicy
    self.openFileUsageChecker = openFileUsageChecker
    self.planLifetime = max(planLifetime, 1)
    self.now = now
  }

  public func prepareDeletion(
    installationIDs: Set<ModelInstallation.ID>,
    currentInventory: [ModelInstallation],
    sources: [ScanSource]
  ) async throws -> DeletionPlan {
    guard !installationIDs.isEmpty else { throw ActionExecutorError.noSelection }
    let selected = currentInventory.filter { installationIDs.contains($0.id) }
    guard selected.count == installationIDs.count else {
      throw ActionExecutorError.inventoryChanged
    }

    let grouped = Dictionary(grouping: selected, by: \.providerID)
    let selectedSourceIDs = Set(selected.map(\.sourceID))
    let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    let sourceApprovals = try selectedSourceIDs.sorted().map { sourceID in
      guard let source = sourcesByID[sourceID], source.isEnabled,
        source.accessState == .allowed,
        let rootIdentity = source.rootIdentity
      else {
        throw ActionExecutorError.sourceUnavailable(sourceID)
      }
      do {
        try SourceRootPolicy().revalidate(
          rootURL: source.rootURL,
          volumeIdentity: source.volumeIdentity,
          expected: rootIdentity
        )
      } catch {
        throw ActionExecutorError.sourceUnavailable(sourceID)
      }
      return DeletionSourceApproval(
        sourceID: source.id,
        rootURL: source.rootURL,
        volumeIdentity: source.volumeIdentity,
        rootIdentity: rootIdentity
      )
    }
    var providerPlans: [ProviderDeletionPlan] = []
    for providerID in grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let adapter = registry.adapter(for: providerID) else {
        throw ActionExecutorError.adapterUnavailable(providerID)
      }
      let context = DeletionPlanningContext(
        selectedInstallations: grouped[providerID] ?? [],
        currentInventory: currentInventory,
        sources: sources
      )
      providerPlans.append(try await adapter.makeDeletionPlan(context: context))
    }

    let createdAt = now()
    let operations = providerPlans.flatMap(\.operations)
    let openPaths = await openFileUsageChecker.openTargetPaths(
      in: operations.compactMap(\.fileTarget)
    )
    let plan = DeletionPlan(
      id: UUID(),
      generationID: UUID(),
      createdAt: createdAt,
      expiresAt: createdAt.addingTimeInterval(planLifetime),
      providerPlans: providerPlans,
      conflicts: Self.conflicts(in: operations)
        + Self.openFileConflicts(
          in: operations,
          openPaths: openPaths
        ),
      sourceApprovals: sourceApprovals
    )
    activePlan = plan
    return plan
  }

  public func cancel(planID: DeletionPlan.ID) {
    guard activePlan?.id == planID else { return }
    activePlan = nil
  }

  public func execute(
    _ plan: DeletionPlan,
    currentInventory: [ModelInstallation],
    sources: [ScanSource],
    confirmedIrreversible: Bool
  ) async throws -> DeletionExecutionReport {
    let startedAt = now()
    do {
      try validatePlanBeforeRevalidation(
        plan,
        currentInventory: currentInventory,
        confirmedIrreversible: confirmedIrreversible
      )
      try await revalidate(plan, currentInventory: currentInventory, sources: sources)
    } catch {
      activePlan = nil
      let report = DeletionExecutionReport(
        planID: plan.id,
        startedAt: startedAt,
        completedAt: now(),
        status: .blocked,
        operationResults: plan.operations.map {
          DeletionOperationResult(id: $0.id, status: .skipped, resultCode: "REVALIDATION_BLOCKED")
        },
        affectedSourceIDs: plan.sourceIDs,
        expectedReclaimableByteCount: plan.expectedReclaimableByteCount
      )
      await appendAudit(for: plan, report: report)
      throw error
    }

    activePlan = nil
    var results: [DeletionOperationResult] = []
    var encounteredFailure = false
    for operation in plan.operations {
      guard !encounteredFailure else {
        results.append(
          DeletionOperationResult(
            id: operation.id,
            status: .skipped,
            resultCode: "SKIPPED_AFTER_FAILURE"
          )
        )
        continue
      }
      do {
        switch operation.payload {
        case .trash(let target):
          try targetPolicy.revalidate(target)
          try await trashMover.moveToTrash(target.url)
        case .provider(let request):
          try revalidateSourceApprovals(for: operation, in: plan, sources: sources)
          guard let adapter = registry.adapter(for: operation.providerID) else {
            throw ActionExecutorError.adapterUnavailable(operation.providerID)
          }
          try await adapter.execute(request)
        }
        results.append(
          DeletionOperationResult(id: operation.id, status: .succeeded, resultCode: "SUCCEEDED")
        )
      } catch {
        encounteredFailure = true
        results.append(
          DeletionOperationResult(id: operation.id, status: .failed, resultCode: "OPERATION_FAILED")
        )
      }
    }

    let succeededCount = results.count { $0.status == .succeeded }
    let failedCount = results.count { $0.status == .failed }
    let status: DeletionExecutionStatus
    if failedCount == 0 {
      status = .succeeded
    } else if succeededCount > 0 {
      status = .partial
    } else {
      status = .failed
    }
    let report = DeletionExecutionReport(
      planID: plan.id,
      startedAt: startedAt,
      completedAt: now(),
      status: status,
      operationResults: results,
      affectedSourceIDs: affectedSourceIDs(for: plan),
      expectedReclaimableByteCount: plan.expectedReclaimableByteCount
    )
    await appendAudit(for: plan, report: report)
    return report
  }

  public func auditEntries() async -> [ActionAuditEntry] {
    (try? await auditStore.entries()) ?? []
  }

  public func clearAudit() async throws {
    try await auditStore.clear()
  }

  private func validatePlanBeforeRevalidation(
    _ plan: DeletionPlan,
    currentInventory: [ModelInstallation],
    confirmedIrreversible: Bool
  ) throws {
    guard let activePlan, activePlan == plan else { throw ActionExecutorError.planNotActive }
    guard now() <= plan.expiresAt else { throw ActionExecutorError.planExpired }
    guard plan.conflicts.isEmpty else { throw ActionExecutorError.planConflict }
    guard !plan.requiresIrreversibleConfirmation || confirmedIrreversible else {
      throw ActionExecutorError.irreversibleConfirmationRequired
    }
    let selectedIDs = Set(plan.models.map(\.id))
    guard selectedIDs.isSubset(of: Set(currentInventory.map(\.id))) else {
      throw ActionExecutorError.inventoryChanged
    }
  }

  private func revalidate(
    _ plan: DeletionPlan,
    currentInventory: [ModelInstallation],
    sources: [ScanSource]
  ) async throws {
    let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    for approval in plan.sourceApprovals {
      guard let source = sourcesByID[approval.sourceID], source.isEnabled,
        source.accessState == .allowed,
        source.rootURL.standardizedFileURL == approval.rootURL.standardizedFileURL,
        source.rootIdentity == approval.rootIdentity
      else {
        throw ActionExecutorError.sourceUnavailable(approval.sourceID)
      }
      do {
        try SourceRootPolicy().revalidate(
          rootURL: source.rootURL,
          volumeIdentity: source.volumeIdentity,
          expected: approval.rootIdentity
        )
      } catch {
        throw ActionExecutorError.targetRevalidationFailed
      }
    }
    let openPaths = await openFileUsageChecker.openTargetPaths(
      in: plan.operations.compactMap(\.fileTarget)
    )
    guard openPaths.isEmpty else { throw ActionExecutorError.targetInUse }
    for operation in plan.operations {
      guard case .trash(let target) = operation.payload else { continue }
      guard let source = sourcesByID[target.sourceID], source.isEnabled,
        source.accessState == .allowed,
        source.rootURL.standardizedFileURL == target.sourceRootURL.standardizedFileURL
      else {
        throw ActionExecutorError.sourceUnavailable(target.sourceID)
      }
      do {
        try targetPolicy.revalidate(target)
      } catch {
        throw ActionExecutorError.targetRevalidationFailed
      }
    }

    let selectedByID = Dictionary(uniqueKeysWithValues: currentInventory.map { ($0.id, $0) })
    for providerPlan in plan.providerPlans {
      guard let adapter = registry.adapter(for: providerPlan.providerID) else {
        throw ActionExecutorError.adapterUnavailable(providerPlan.providerID)
      }
      let selected = try providerPlan.models.map { summary in
        guard let installation = selectedByID[summary.id] else {
          throw ActionExecutorError.inventoryChanged
        }
        return installation
      }
      do {
        try await adapter.revalidate(
          providerPlan,
          context: DeletionPlanningContext(
            selectedInstallations: selected,
            currentInventory: currentInventory,
            sources: sources
          )
        )
      } catch {
        throw ActionExecutorError.providerRevalidationFailed(providerPlan.providerID)
      }
    }
  }

  private func revalidateSourceApprovals(
    for operation: DeletionOperation,
    in plan: DeletionPlan,
    sources: [ScanSource]
  ) throws {
    let installationIDs = Set(operation.installationIDs)
    let sourceIDs = Set(plan.models.filter { installationIDs.contains($0.id) }.map(\.sourceID))
    let approvals = Dictionary(uniqueKeysWithValues: plan.sourceApprovals.map { ($0.sourceID, $0) })
    let current = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    for sourceID in sourceIDs {
      guard let approval = approvals[sourceID], let source = current[sourceID],
        source.isEnabled, source.accessState == .allowed,
        source.rootURL.standardizedFileURL == approval.rootURL.standardizedFileURL,
        source.rootIdentity == approval.rootIdentity
      else {
        throw ActionExecutorError.sourceUnavailable(sourceID)
      }
      do {
        try SourceRootPolicy().revalidate(
          rootURL: source.rootURL,
          volumeIdentity: source.volumeIdentity,
          expected: approval.rootIdentity
        )
      } catch {
        throw ActionExecutorError.targetRevalidationFailed
      }
    }
  }

  private func appendAudit(for plan: DeletionPlan, report: DeletionExecutionReport) async {
    let entry = ActionAuditEntry(
      occurredAt: report.completedAt,
      providerIDs: Array(Set(plan.providerPlans.map(\.providerID))),
      operationCount: report.operationResults.count,
      succeededCount: report.operationResults.count { $0.status == .succeeded },
      failedCount: report.operationResults.count { $0.status == .failed },
      status: report.status,
      includedIrreversibleOperation: plan.requiresIrreversibleConfirmation
    )
    try? await auditStore.append(entry)
  }

  private func affectedSourceIDs(for plan: DeletionPlan) -> Set<ScanSource.ID> {
    return plan.sourceIDs
  }

  private static func conflicts(in operations: [DeletionOperation]) -> [DeletionConflict] {
    var conflicts: [DeletionConflict] = []
    for leftIndex in operations.indices {
      for rightIndex in operations.indices where rightIndex > leftIndex {
        let left = operations[leftIndex]
        let right = operations[rightIndex]
        guard targetsOverlap(left.payload, right.payload) else { continue }
        let reason: DeletionConflictReason =
          left.providerID == right.providerID ? .overlappingTargets : .providerMismatch
        conflicts.append(
          DeletionConflict(
            id: "\(reason.rawValue):\(left.id):\(right.id)",
            reason: reason,
            operationIDs: [left.id, right.id],
            installationIDs: Array(Set(left.installationIDs + right.installationIDs))
          )
        )
      }
    }
    return conflicts
  }

  private static func openFileConflicts(
    in operations: [DeletionOperation],
    openPaths: Set<String>
  ) -> [DeletionConflict] {
    operations.compactMap { operation in
      guard let target = operation.fileTarget,
        openPaths.contains(target.url.standardizedFileURL.path)
      else { return nil }
      return DeletionConflict(
        id: "modelInUse:\(operation.id)",
        reason: .modelInUse,
        operationIDs: [operation.id],
        installationIDs: operation.installationIDs
      )
    }
  }

  private static func targetsOverlap(
    _ left: DeletionOperationPayload,
    _ right: DeletionOperationPayload
  ) -> Bool {
    switch (left, right) {
    case (.trash(let leftTarget), .trash(let rightTarget)):
      let leftPath = leftTarget.url.standardizedFileURL.path
      let rightPath = rightTarget.url.standardizedFileURL.path
      return leftPath == rightPath || leftPath.hasPrefix(rightPath + "/")
        || rightPath.hasPrefix(leftPath + "/")
    case (.provider(let leftRequest), .provider(let rightRequest)):
      return leftRequest == rightRequest
    default:
      return false
    }
  }
}

private extension DeletionOperation {
  var fileTarget: DeletionFileTarget? {
    guard case .trash(let target) = payload else { return nil }
    return target
  }
}
