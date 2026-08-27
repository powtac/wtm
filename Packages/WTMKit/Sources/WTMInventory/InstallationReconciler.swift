import Foundation
import WTMDomain

/// Removes duplicate installation views created when a broad manual source overlaps a
/// provider-owned source. Distinct paths and volumes remain distinct installations.
struct InstallationReconciler: Sendable {
  func reconcile(_ installations: [ModelInstallation]) -> [ModelInstallation] {
    var canonical: [ModelInstallation] = []
    var canonicalIDs: Set<ModelInstallation.ID> = []
    _ = merge(installations, into: &canonical, canonicalIDs: &canonicalIDs)
    return canonical
  }

  /// Merges a bounded batch in place and returns only newly accepted installations.
  /// This avoids rebuilding the complete canonical array for every streamed batch.
  func merge(
    _ incoming: [ModelInstallation],
    into canonical: inout [ModelInstallation],
    canonicalIDs: inout Set<ModelInstallation.ID>
  ) -> [ModelInstallation] {
    var accepted: [ModelInstallation] = []

    for installation in incoming {
      if let sameID = canonical.firstIndex(where: { $0.id == installation.id }) {
        canonical[sameID] = installation
        continue
      }

      if canonical.contains(where: { shadows(installation, preferred: $0) }) {
        continue
      }

      let shadowedIDs = canonical.filter { existing in
        shadows(existing, preferred: installation)
      }.map(\.id)
      if !shadowedIDs.isEmpty {
        let shadowedIDSet = Set(shadowedIDs)
        canonical.removeAll { shadowedIDSet.contains($0.id) }
        canonicalIDs.subtract(shadowedIDSet)
      }
      canonical.append(installation)
      canonicalIDs.insert(installation.id)
      accepted.append(installation)
    }

    return accepted
  }

  private func shadows(
    _ candidate: ModelInstallation,
    preferred: ModelInstallation
  ) -> Bool {
    guard providerPriority(candidate.providerID) >= providerPriority(preferred.providerID) else {
      return false
    }

    let candidatePaths = artifactPaths(candidate)
    let preferredPaths = artifactPaths(preferred)
    guard !candidatePaths.isEmpty else { return false }

    if candidate.providerID == preferred.providerID {
      return candidate.rootURL.standardizedFileURL == preferred.rootURL.standardizedFileURL
        && candidatePaths == preferredPaths
    }

    if candidate.providerID == .manual, preferred.providerID != .manual {
      return candidatePaths.isSubset(of: preferredPaths)
    }
    if candidate.providerID == .huggingFace, preferred.providerID == .mlx {
      return preferredPaths.isSubset(of: candidatePaths)
    }
    return false
  }

  private func artifactPaths(_ installation: ModelInstallation) -> Set<String> {
    Set(installation.artifacts.map { $0.url.standardizedFileURL.path })
  }

  private func providerPriority(_ providerID: ProviderID) -> Int {
    switch providerID {
    case .mlx: 0
    case .manual: 2
    default: 1
    }
  }
}
