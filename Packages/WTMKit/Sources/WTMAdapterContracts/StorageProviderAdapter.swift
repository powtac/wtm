import Foundation
import WTMDomain

public struct AdapterScanResult: Sendable {
  public let source: ScanSource
  public let installations: [ModelInstallation]
  public let issues: [InventoryIssue]
  public let scannedAt: Date

  public init(
    source: ScanSource,
    installations: [ModelInstallation],
    issues: [InventoryIssue] = [],
    scannedAt: Date = .now
  ) {
    self.source = source
    self.installations = installations
    self.issues = issues
    self.scannedAt = scannedAt
  }
}

/// Read-only boundary implemented by every storage provider shipped in Phase 1.
public protocol StorageProviderAdapter: Sendable {
  var id: ProviderID { get }
  var displayName: String { get }

  func scan(source: ScanSource) async -> AdapterScanResult
}
