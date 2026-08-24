import WTMDomain

public enum StorageActionAdapterError: Error, Equatable, Sendable {
  case invalidSelection
  case noDeletableArtifacts
  case sourceUnavailable(ScanSource.ID)
  case pathOutsideSource
  case fileIdentityUnavailable
  case providerStateChanged
  case providerUnavailable
  case modelInUse(String)
  case unsupportedProviderRequest
  case providerRequestFailed
}

/// Provider-specific planning and execution boundary for Phase 2 cleanup.
///
/// Implementations return data-only operations. Filesystem mutation remains centralized in
/// `ActionExecutor`; an adapter may execute only its reviewed provider request kind.
public protocol StorageActionAdapter: Sendable {
  var id: ProviderID { get }
  var displayName: String { get }

  func makeDeletionPlan(context: DeletionPlanningContext) async throws -> ProviderDeletionPlan
  func revalidate(
    _ plan: ProviderDeletionPlan,
    context: DeletionPlanningContext
  ) async throws
  func execute(_ request: ProviderDeletionRequest) async throws
}

extension StorageActionAdapter {
  public func revalidate(
    _ plan: ProviderDeletionPlan,
    context: DeletionPlanningContext
  ) async throws {
    let replacement = try await makeDeletionPlan(context: context)
    guard replacement == plan else {
      throw StorageActionAdapterError.providerStateChanged
    }
  }

  public func execute(_ request: ProviderDeletionRequest) async throws {
    throw StorageActionAdapterError.unsupportedProviderRequest
  }
}
