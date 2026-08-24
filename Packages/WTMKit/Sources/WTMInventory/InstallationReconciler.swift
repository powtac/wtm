import Foundation
import WTMDomain

/// Removes duplicate installation views created when a broad manual source overlaps a
/// provider-owned source. Distinct paths and volumes remain distinct installations.
struct InstallationReconciler: Sendable {
  func reconcile(_ installations: [ModelInstallation]) -> [ModelInstallation] {
    var canonical: [ModelInstallation] = []

    for installation in installations {
      if let sameID = canonical.firstIndex(where: { $0.id == installation.id }) {
        canonical[sameID] = installation
        continue
      }

      if canonical.contains(where: { shadows(installation, preferred: $0) }) {
        continue
      }

      canonical.removeAll { existing in
        shadows(existing, preferred: installation)
      }
      canonical.append(installation)
    }

    return canonical
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

    guard candidate.providerID == .manual, preferred.providerID != .manual else { return false }
    return candidatePaths.isSubset(of: preferredPaths)
  }

  private func artifactPaths(_ installation: ModelInstallation) -> Set<String> {
    Set(installation.artifacts.map { $0.url.standardizedFileURL.path })
  }

  private func providerPriority(_ providerID: ProviderID) -> Int {
    providerID == .manual ? 1 : 0
  }
}
