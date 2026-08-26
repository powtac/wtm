import Foundation

public enum DeletionReversibility: String, Codable, CaseIterable, Sendable {
  case trash
  case irreversible
}

public enum DeletionWarning: String, Codable, CaseIterable, Sendable {
  case externalUsageNotVerified
  case freeSpaceIsEstimated
}

public struct DeletionFileIdentity: Hashable, Codable, Sendable {
  public let deviceID: UInt64
  public let fileID: UInt64
  public let mode: UInt32
  public let byteCount: Int64
  public let modificationSeconds: Int64
  public let modificationNanoseconds: Int64

  public init(
    deviceID: UInt64,
    fileID: UInt64,
    mode: UInt32,
    byteCount: Int64,
    modificationSeconds: Int64,
    modificationNanoseconds: Int64
  ) {
    self.deviceID = deviceID
    self.fileID = fileID
    self.mode = mode
    self.byteCount = byteCount
    self.modificationSeconds = modificationSeconds
    self.modificationNanoseconds = modificationNanoseconds
  }
}

public struct DeletionModelSummary: Identifiable, Hashable, Codable, Sendable {
  public let id: ModelInstallation.ID
  public let displayName: String
  public let providerID: ProviderID
  public let sourceID: ScanSource.ID
  public let artifactCount: Int
  public let allocatedByteCount: Int64

  public init(
    id: ModelInstallation.ID,
    displayName: String,
    providerID: ProviderID,
    sourceID: ScanSource.ID,
    artifactCount: Int,
    allocatedByteCount: Int64
  ) {
    self.id = id
    self.displayName = displayName
    self.providerID = providerID
    self.sourceID = sourceID
    self.artifactCount = artifactCount
    self.allocatedByteCount = allocatedByteCount
  }
}

public struct DeletionFileTarget: Hashable, Codable, Sendable {
  public let url: URL
  public let sourceID: ScanSource.ID
  public let sourceRootURL: URL
  public let sourceRootIdentity: SourceRootIdentity
  public let identity: DeletionFileIdentity
  public let allocatedByteCount: Int64
  public let displayName: String

  public init(
    url: URL,
    sourceID: ScanSource.ID,
    sourceRootURL: URL,
    sourceRootIdentity: SourceRootIdentity,
    identity: DeletionFileIdentity,
    allocatedByteCount: Int64,
    displayName: String
  ) {
    self.url = url
    self.sourceID = sourceID
    self.sourceRootURL = sourceRootURL
    self.sourceRootIdentity = sourceRootIdentity
    self.identity = identity
    self.allocatedByteCount = allocatedByteCount
    self.displayName = displayName
  }
}

public enum ProviderDeletionRequestKind: String, Codable, CaseIterable, Sendable {
  case ollamaModel
}

public struct ProviderDeletionRequest: Hashable, Codable, Sendable {
  public let kind: ProviderDeletionRequestKind
  public let identifier: String

  public init(kind: ProviderDeletionRequestKind, identifier: String) {
    self.kind = kind
    self.identifier = identifier
  }
}

public enum DeletionOperationPayload: Hashable, Codable, Sendable {
  case trash(DeletionFileTarget)
  case provider(ProviderDeletionRequest)
}

public struct DeletionOperation: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let providerID: ProviderID
  public let installationIDs: [ModelInstallation.ID]
  public let reversibility: DeletionReversibility
  public let expectedReclaimableByteCount: Int64
  public let payload: DeletionOperationPayload

  public init(
    id: String,
    providerID: ProviderID,
    installationIDs: [ModelInstallation.ID],
    reversibility: DeletionReversibility,
    expectedReclaimableByteCount: Int64,
    payload: DeletionOperationPayload
  ) {
    self.id = id
    self.providerID = providerID
    self.installationIDs = installationIDs.sorted()
    self.reversibility = reversibility
    self.expectedReclaimableByteCount = max(expectedReclaimableByteCount, 0)
    self.payload = payload
  }
}

public enum RetainedDependencyReason: String, Codable, CaseIterable, Sendable {
  case remainingReference
  case protectedIdentityOrSecret
  case unknownOwnership
}

public struct RetainedDeletionDependency: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let displayName: String
  public let allocatedByteCount: Int64
  public let reason: RetainedDependencyReason
  public let installationIDs: [ModelInstallation.ID]

  public init(
    id: String,
    displayName: String,
    allocatedByteCount: Int64,
    reason: RetainedDependencyReason,
    installationIDs: [ModelInstallation.ID]
  ) {
    self.id = id
    self.displayName = displayName
    self.allocatedByteCount = max(allocatedByteCount, 0)
    self.reason = reason
    self.installationIDs = installationIDs.sorted()
  }
}

public enum DeletionConflictReason: String, Codable, CaseIterable, Sendable {
  case overlappingTargets
  case providerMismatch
  case modelInUse
}

public struct DeletionConflict: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let reason: DeletionConflictReason
  public let operationIDs: [DeletionOperation.ID]
  public let installationIDs: [ModelInstallation.ID]

  public init(
    id: String,
    reason: DeletionConflictReason,
    operationIDs: [DeletionOperation.ID],
    installationIDs: [ModelInstallation.ID]
  ) {
    self.id = id
    self.reason = reason
    self.operationIDs = operationIDs.sorted()
    self.installationIDs = installationIDs.sorted()
  }
}

public struct ProviderDeletionPlan: Hashable, Codable, Sendable {
  public let providerID: ProviderID
  public let models: [DeletionModelSummary]
  public let operations: [DeletionOperation]
  public let retainedDependencies: [RetainedDeletionDependency]
  public let warnings: Set<DeletionWarning>

  public init(
    providerID: ProviderID,
    models: [DeletionModelSummary],
    operations: [DeletionOperation],
    retainedDependencies: [RetainedDeletionDependency] = [],
    warnings: Set<DeletionWarning> = []
  ) {
    self.providerID = providerID
    self.models = models.sorted { $0.id < $1.id }
    self.operations = operations.sorted { $0.id < $1.id }
    self.retainedDependencies = retainedDependencies.sorted { $0.id < $1.id }
    self.warnings = warnings
  }
}

/// Immutable, short-lived preview consumed once by `ActionExecutor`.
///
/// Example: create a plan from the current inventory, show all operations to the user, then
/// pass the unchanged value back for revalidation and execution.
public struct DeletionPlan: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let generationID: UUID
  public let createdAt: Date
  public let expiresAt: Date
  public let providerPlans: [ProviderDeletionPlan]
  public let conflicts: [DeletionConflict]
  public let sourceApprovals: [DeletionSourceApproval]

  public init(
    id: UUID,
    generationID: UUID,
    createdAt: Date,
    expiresAt: Date,
    providerPlans: [ProviderDeletionPlan],
    conflicts: [DeletionConflict],
    sourceApprovals: [DeletionSourceApproval] = []
  ) {
    self.id = id
    self.generationID = generationID
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.providerPlans = providerPlans.sorted { $0.providerID.rawValue < $1.providerID.rawValue }
    self.conflicts = conflicts.sorted { $0.id < $1.id }
    self.sourceApprovals = sourceApprovals.sorted { $0.sourceID < $1.sourceID }
  }

  public var models: [DeletionModelSummary] { providerPlans.flatMap(\.models) }
  public var operations: [DeletionOperation] { providerPlans.flatMap(\.operations) }
  public var retainedDependencies: [RetainedDeletionDependency] {
    providerPlans.flatMap(\.retainedDependencies)
  }
  public var sourceIDs: Set<ScanSource.ID> {
    Set(models.map(\.sourceID))
  }
  public var expectedReclaimableByteCount: Int64 {
    operations.reduce(0) { $0 + $1.expectedReclaimableByteCount }
  }
  public var requiresIrreversibleConfirmation: Bool {
    operations.contains { $0.reversibility == .irreversible }
  }
}

public struct DeletionSourceApproval: Hashable, Codable, Sendable {
  public let sourceID: ScanSource.ID
  public let rootURL: URL
  public let volumeIdentity: VolumeIdentity?
  public let rootIdentity: SourceRootIdentity

  public init(
    sourceID: ScanSource.ID,
    rootURL: URL,
    volumeIdentity: VolumeIdentity?,
    rootIdentity: SourceRootIdentity
  ) {
    self.sourceID = sourceID
    self.rootURL = rootURL
    self.volumeIdentity = volumeIdentity
    self.rootIdentity = rootIdentity
  }
}

public struct DeletionPlanningContext: Sendable {
  public let selectedInstallations: [ModelInstallation]
  public let currentInventory: [ModelInstallation]
  public let sources: [ScanSource]

  public init(
    selectedInstallations: [ModelInstallation],
    currentInventory: [ModelInstallation],
    sources: [ScanSource]
  ) {
    self.selectedInstallations = selectedInstallations
    self.currentInventory = currentInventory
    self.sources = sources
  }

  public func source(for sourceID: ScanSource.ID) -> ScanSource? {
    sources.first { $0.id == sourceID }
  }
}

public enum DeletionOperationStatus: String, Codable, CaseIterable, Sendable {
  case succeeded
  case failed
  case skipped
}

public struct DeletionOperationResult: Identifiable, Hashable, Codable, Sendable {
  public let id: DeletionOperation.ID
  public let status: DeletionOperationStatus
  public let resultCode: String

  public init(id: DeletionOperation.ID, status: DeletionOperationStatus, resultCode: String) {
    self.id = id
    self.status = status
    self.resultCode = resultCode
  }
}

public enum DeletionExecutionStatus: String, Codable, CaseIterable, Sendable {
  case succeeded
  case partial
  case blocked
  case failed
}

public struct DeletionExecutionReport: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let planID: DeletionPlan.ID
  public let startedAt: Date
  public let completedAt: Date
  public let status: DeletionExecutionStatus
  public let operationResults: [DeletionOperationResult]
  public let affectedSourceIDs: Set<ScanSource.ID>
  public let expectedReclaimableByteCount: Int64

  public init(
    id: UUID = UUID(),
    planID: DeletionPlan.ID,
    startedAt: Date,
    completedAt: Date,
    status: DeletionExecutionStatus,
    operationResults: [DeletionOperationResult],
    affectedSourceIDs: Set<ScanSource.ID>,
    expectedReclaimableByteCount: Int64
  ) {
    self.id = id
    self.planID = planID
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.status = status
    self.operationResults = operationResults
    self.affectedSourceIDs = affectedSourceIDs
    self.expectedReclaimableByteCount = max(expectedReclaimableByteCount, 0)
  }
}
