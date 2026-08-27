import Foundation
import WTMDomain

/// Orders the operational scan queue without changing what triggered the scan.
///
/// More deeply nested roots are scanned first because they represent a more specific user
/// selection. Persisted source order remains the final deterministic tie-breaker.
public struct SourcePrioritizer: Sendable {
  public init() {}

  public func prioritize(_ sources: [ScanSource]) -> [ScanSource] {
    ScanSourcePathFilter().filter(sources).enumerated()
      .sorted { left, right in
        let leftSource = left.element
        let rightSource = right.element
        let leftDepth = pathDepth(of: leftSource.rootURL)
        let rightDepth = pathDepth(of: rightSource.rootURL)

        if leftDepth != rightDepth { return leftDepth > rightDepth }

        let leftProviderPriority = providerPriority(leftSource.providerID)
        let rightProviderPriority = providerPriority(rightSource.providerID)
        if leftProviderPriority != rightProviderPriority {
          return leftProviderPriority < rightProviderPriority
        }

        return left.offset < right.offset
      }
      .map(\.element)
  }

  private func pathDepth(of url: URL) -> Int {
    url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.count
  }

  private func providerPriority(_ providerID: ProviderID) -> Int {
    providerID == .manual ? 1 : 0
  }
}
