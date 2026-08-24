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

public struct AdapterScanBatch: Sendable {
  public let installations: [ModelInstallation]
  public let issues: [InventoryIssue]

  public init(
    installations: [ModelInstallation],
    issues: [InventoryIssue] = []
  ) {
    self.installations = installations
    self.issues = issues
  }
}

/// Read-only boundary implemented by every storage provider shipped in Phase 1.
public protocol StorageProviderAdapter: Sendable {
  var id: ProviderID { get }
  var displayName: String { get }

  func scan(source: ScanSource) async -> AdapterScanResult
  func scanBatches(source: ScanSource) -> AsyncStream<AdapterScanBatch>
}

extension StorageProviderAdapter {
  public func scanBatches(source: ScanSource) -> AsyncStream<AdapterScanBatch> {
    AsyncStream { continuation in
      let task = Task {
        let result = await scan(source: source)
        guard !Task.isCancelled else {
          continuation.finish()
          return
        }
        continuation.yield(
          AdapterScanBatch(installations: result.installations, issues: result.issues)
        )
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
