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
    var retained: [RetainedDeletionDependency] = []
    for installation in selected {
      guard let source = context.source(for: installation.sourceID), source.isEnabled,
        source.accessState == .allowed
      else {
        throw StorageActionAdapterError.sourceUnavailable(installation.sourceID)
      }
      for artifact in installation.artifacts {
        if configurationPolicy.isSecretSuspect(artifact.url) {
          retained.append(
            retainedDependency(
              artifact: artifact,
              installationID: installation.id,
              reason: .protectedIdentityOrSecret
            )
          )
          continue
        }
        guard let physicalIdentifier = artifact.physicalIdentifier else {
          retained.append(
            retainedDependency(
              artifact: artifact,
              installationID: installation.id,
              reason: .unknownOwnership
            )
          )
          continue
        }
        guard !remainingPhysicalIDs.contains(physicalIdentifier) else {
          retained.append(
            retainedDependency(
              artifact: artifact,
              installationID: installation.id,
              reason: .remainingReference
            )
          )
          continue
        }

        let path = artifact.url.standardizedFileURL.path
        let identity: DeletionFileIdentity
        do {
          identity = try targetPolicy.captureIdentity(
            for: artifact.url,
            under: source.rootURL
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
            allocatedByteCount: artifact.allocatedByteCount,
            installationIDs: []
          )
        guard aggregate.identity == identity, aggregate.source.id == source.id else {
          throw StorageActionAdapterError.providerStateChanged
        }
        aggregate.installationIDs.insert(installation.id)
        aggregate.allocatedByteCount = max(
          aggregate.allocatedByteCount,
          artifact.allocatedByteCount
        )
        aggregates[path] = aggregate
      }
    }

    let operations = aggregates.values.map { aggregate in
      let target = DeletionFileTarget(
        url: aggregate.url,
        sourceID: aggregate.source.id,
        sourceRootURL: aggregate.source.rootURL,
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
      retainedDependencies: retained,
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

  private func retainedDependency(
    artifact: Artifact,
    installationID: ModelInstallation.ID,
    reason: RetainedDependencyReason
  ) -> RetainedDeletionDependency {
    RetainedDeletionDependency(
      id: "manual:retained:\(reason.rawValue):\(artifact.url.standardizedFileURL.path)",
      displayName: artifact.url.lastPathComponent,
      allocatedByteCount: artifact.allocatedByteCount,
      reason: reason,
      installationIDs: [installationID]
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
