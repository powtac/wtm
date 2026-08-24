import Foundation
import WTMDomain

public struct InventoryStorageBreakdown: Sendable {
  public let exclusiveByteCountByInstallationID: [ModelInstallation.ID: Int64]
  public let sharedByteCount: Int64
  public let unknownByteCount: Int64

  public init(installations: [ModelInstallation]) {
    struct ArtifactReference {
      let installationID: ModelInstallation.ID
      let artifact: Artifact
    }

    var known: [String: [ArtifactReference]] = [:]
    var exclusive: [ModelInstallation.ID: Int64] = [:]
    var unknown: Int64 = 0
    for installation in installations {
      for artifact in installation.artifacts {
        guard let identifier = artifact.physicalIdentifier else {
          unknown += artifact.allocatedByteCount
          continue
        }
        known[identifier, default: []].append(
          ArtifactReference(installationID: installation.id, artifact: artifact)
        )
      }
    }

    var shared: Int64 = 0
    for references in known.values {
      let allocatedByteCount = references.map(\.artifact.allocatedByteCount).max() ?? 0
      let installationIDs = Set(references.map(\.installationID))
      if references.count > 1 || installationIDs.count > 1 {
        shared += allocatedByteCount
      } else if let installationID = references.first?.installationID {
        exclusive[installationID, default: 0] += allocatedByteCount
      }
    }

    exclusiveByteCountByInstallationID = exclusive
    sharedByteCount = shared
    unknownByteCount = unknown
  }

  public var totalByteCount: Int64 {
    exclusiveByteCountByInstallationID.values.reduce(0, +) + sharedByteCount + unknownByteCount
  }

  public func exclusiveByteCount(for installationID: ModelInstallation.ID) -> Int64 {
    exclusiveByteCountByInstallationID[installationID, default: 0]
  }
}
