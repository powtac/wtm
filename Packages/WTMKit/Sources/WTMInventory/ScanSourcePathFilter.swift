import Foundation
import WTMDomain

/// Removes duplicate enabled scan roots for the same provider.
///
/// Nested roots are intentionally retained. Their scan order is owned by `SourcePrioritizer`,
/// because a specifically selected child can produce useful results before its parent scan.
public struct ScanSourcePathFilter: Sendable {
  public init() {}

  public func filter(_ sources: [ScanSource]) -> [ScanSource] {
    var retained: [ScanSource] = []

    for source in sources where source.isEnabled {
      guard
        !retained.contains(where: {
          isScanCapable($0)
            && isScanCapable(source)
            && $0.providerID == source.providerID
            && canonicalPath(for: $0.rootURL) == canonicalPath(for: source.rootURL)
        })
      else { continue }
      retained.append(source)
    }

    return retained
  }

  private func isScanCapable(_ source: ScanSource) -> Bool {
    source.accessState == .allowed || source.accessState == .limited
  }

  private func canonicalPath(for url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
  }
}
