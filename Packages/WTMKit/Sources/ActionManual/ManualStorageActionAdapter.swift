import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct ManualStorageActionAdapter: StorageActionAdapter {
  public let id = ProviderID.manual
  public let displayName = "Manual Folder"

  private let targetPolicy: DeletionTargetPolicy
  private let configurationPolicy: ConfigurationFilePolicy

  public init(
    targetPolicy: DeletionTargetPolicy = DeletionTargetPolicy(),
    configurationPolicy: ConfigurationFilePolicy = ConfigurationFilePolicy()
  ) {
    self.targetPolicy = targetPolicy
    self.configurationPolicy = configurationPolicy
  }

  public func makeDeletionPlan(context: DeletionPlanningContext) async throws
    -> ProviderDeletionPlan
  {
    let selected = context.selectedInstallations.filter { $0.providerID == id }
    guard selected.count == context.selectedInstallations.count, !selected.isEmpty else {
      throw StorageActionAdapterError.invalidSelection
    }
    let selectedIDs = Set(selected.map(\.id))
    let remainingPhysicalIDs = Set(
      context.currentInventory
        .filter { !selectedIDs.contains($0.id) }
        .flatMap(\.artifacts)
        .compactMap(\.physicalIdentifier)
    )

    var aggregates: [String: TargetAggregate] = [:]
    var retainedByID: [String: RetainedDeletionDependency] = [:]
    var countedPhysicalIDs: Set<String> = []
    for installation in selected {
      guard let source = context.source(for: installation.sourceID), source.isEnabled,
        source.accessState == .allowed
      else {
        throw StorageActionAdapterError.sourceUnavailable(installation.sourceID)
      }
      do {
        try targetPolicy.validateWritableVolume(containing: source.rootURL)
      } catch {
        throw StorageActionAdapterError.sourceUnavailable(installation.sourceID)
      }
      for artifact in installation.artifacts {
        if configurationPolicy.isSecretSuspect(artifact.url) {
          mergeRetained(
            artifact: artifact,
            installationID: installation.id,
            reason: .protectedIdentityOrSecret,
            into: &retainedByID
          )
          continue
        }
        guard let physicalIdentifier = artifact.physicalIdentifier else {
          mergeRetained(
            artifact: artifact,
            installationID: installation.id,
            reason: .unknownOwnership,
            into: &retainedByID
          )
          continue
        }
        guard !remainingPhysicalIDs.contains(physicalIdentifier) else {
          mergeRetained(
            artifact: artifact,
            installationID: installation.id,
            reason: .remainingReference,
            into: &retainedByID
          )
          continue
        }

        let path = artifact.url.standardizedFileURL.path
        let estimatedReclaimableByteCount =
          countedPhysicalIDs.insert(physicalIdentifier).inserted
          ? artifact.allocatedByteCount : 0
        let identity: DeletionFileIdentity
        guard let rootIdentity = source.rootIdentity else {
          throw StorageActionAdapterError.fileIdentityUnavailable
        }
        do {
          identity = try targetPolicy.captureIdentity(
            for: artifact.url,
            under: source.rootURL,
            volumeIdentity: source.volumeIdentity,
            expectedRootIdentity: rootIdentity
          )
        } catch {
          throw StorageActionAdapterError.fileIdentityUnavailable
        }
        var aggregate =
          aggregates[path]
          ?? TargetAggregate(
            url: artifact.url,
            source: source,
            identity: identity,
            allocatedByteCount: estimatedReclaimableByteCount,
            installationIDs: []
          )
        guard aggregate.identity == identity, aggregate.source.id == source.id else {
          throw StorageActionAdapterError.providerStateChanged
        }
        aggregate.installationIDs.insert(installation.id)
        aggregate.allocatedByteCount = max(
          aggregate.allocatedByteCount,
          estimatedReclaimableByteCount
        )
        aggregates[path] = aggregate
      }
    }

    let operations = try aggregates.values.map { aggregate in
      guard let rootIdentity = aggregate.source.rootIdentity else {
        throw StorageActionAdapterError.fileIdentityUnavailable
      }
      let target = DeletionFileTarget(
        url: aggregate.url,
        sourceID: aggregate.source.id,
        sourceRootURL: aggregate.source.rootURL,
        sourceRootIdentity: rootIdentity,
        identity: aggregate.identity,
        allocatedByteCount: aggregate.allocatedByteCount,
        displayName: aggregate.url.lastPathComponent
      )
      return DeletionOperation(
        id: "manual:trash:\(aggregate.url.standardizedFileURL.path)",
        providerID: id,
        installationIDs: Array(aggregate.installationIDs),
        reversibility: .trash,
        expectedReclaimableByteCount: aggregate.allocatedByteCount,
        payload: .trash(target)
      )
    }
    guard !operations.isEmpty else { throw StorageActionAdapterError.noDeletableArtifacts }

    return ProviderDeletionPlan(
      providerID: id,
      models: selected.map(Self.summary),
      operations: operations,
      retainedDependencies: Array(retainedByID.values),
      warnings: [.externalUsageNotVerified, .freeSpaceIsEstimated]
    )
  }

  private static func summary(_ installation: ModelInstallation) -> DeletionModelSummary {
    DeletionModelSummary(
      id: installation.id,
      displayName: installation.identity.displayName,
      providerID: installation.providerID,
      sourceID: installation.sourceID,
      artifactCount: installation.artifacts.count,
      allocatedByteCount: installation.allocatedByteCount
    )
  }

  private func mergeRetained(
    artifact: Artifact,
    installationID: ModelInstallation.ID,
    reason: RetainedDependencyReason,
    into dependencies: inout [String: RetainedDeletionDependency]
  ) {
    let id = "manual:retained:\(reason.rawValue):\(artifact.url.standardizedFileURL.path)"
    let existing = dependencies[id]
    dependencies[id] = RetainedDeletionDependency(
      id: id,
      displayName: artifact.url.lastPathComponent,
      allocatedByteCount: max(existing?.allocatedByteCount ?? 0, artifact.allocatedByteCount),
      reason: reason,
      installationIDs: Array(Set(existing?.installationIDs ?? []).union([installationID]))
    )
  }
}

private struct TargetAggregate {
  let url: URL
  let source: ScanSource
  let identity: DeletionFileIdentity
  var allocatedByteCount: Int64
  var installationIDs: Set<ModelInstallation.ID>
}
