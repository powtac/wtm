import Foundation
import WTMDomain

/// Removes redundant enabled scan roots for the same provider.
///
/// A readable parent root covers nested roots. Provider-specific roots are kept separate because
/// adapters interpret the same filesystem differently.
public struct ScanSourcePathFilter: Sendable {
  public init() {}

  public func filter(_ sources: [ScanSource]) -> [ScanSource] {
    var retained: [ScanSource] = []

    for source in sources where source.isEnabled {
      guard isScanCapable(source) else {
        retained.append(source)
        continue
      }

      guard !retained.contains(where: { covers($0, source) }) else { continue }
      retained.removeAll { covers(source, $0) }
      retained.append(source)
    }

    return retained
  }

  private func covers(_ covering: ScanSource, _ candidate: ScanSource) -> Bool {
    guard isScanCapable(covering), covering.providerID == candidate.providerID else {
      return false
    }

    let coveringPath = canonicalPath(for: covering.rootURL)
    let candidatePath = canonicalPath(for: candidate.rootURL)
    guard coveringPath != candidatePath else { return true }
    if coveringPath == "/" { return candidatePath.hasPrefix("/") }
    return candidatePath.hasPrefix(coveringPath + "/")
  }

  private func isScanCapable(_ source: ScanSource) -> Bool {
    source.accessState == .allowed || source.accessState == .limited
  }

  private func canonicalPath(for url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
  }
}
