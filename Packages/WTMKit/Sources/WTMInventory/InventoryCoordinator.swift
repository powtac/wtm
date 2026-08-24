import Foundation
import WTMAdapterContracts
import WTMDomain

public struct InventorySnapshot: Sendable {
  public let installations: [ModelInstallation]
  public let issues: [InventoryIssue]
  public let scannedSourceIDs: Set<ScanSource.ID>
  public let scannedAt: Date

  public init(
    installations: [ModelInstallation],
    issues: [InventoryIssue],
    scannedSourceIDs: Set<ScanSource.ID>,
    scannedAt: Date = .now
  ) {
    self.installations = installations
    self.issues = issues
    self.scannedSourceIDs = scannedSourceIDs
    self.scannedAt = scannedAt
  }

  public var uniqueAllocatedByteCount: Int64 {
    var seenPhysicalIdentifiers: Set<String> = []
    var total: Int64 = 0

    for artifact in installations.flatMap(\.artifacts) {
      if let physicalIdentifier = artifact.physicalIdentifier {
        guard seenPhysicalIdentifiers.insert(physicalIdentifier).inserted else { continue }
      }
      total += artifact.allocatedByteCount
    }
    return total
  }
}

/// Coordinates Phase-1 storage adapters without exposing actions or process execution.
public actor InventoryCoordinator {
  private let registry: AdapterRegistry

  public init(registry: AdapterRegistry) {
    self.registry = registry
  }

  public func scan(source: ScanSource) async -> AdapterScanResult {
    guard source.isEnabled, source.accessState == .allowed else {
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [
          InventoryIssue(
            id: "\(source.id):SOURCE_NOT_ALLOWED",
            code: "SOURCE_NOT_ALLOWED",
            severity: .warning,
            sourceID: source.id,
            summary: "The source is not enabled and allowed.",
            affectedURL: source.rootURL
          )
        ]
      )
    }

    guard FileManager.default.fileExists(atPath: source.rootURL.path) else {
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [
          InventoryIssue(
            id: "\(source.id):SOURCE_OFFLINE",
            code: "SOURCE_OFFLINE",
            severity: .warning,
            sourceID: source.id,
            summary: "The source is currently offline.",
            affectedURL: source.rootURL
          )
        ]
      )
    }

    guard FileManager.default.isReadableFile(atPath: source.rootURL.path) else {
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [
          InventoryIssue(
            id: "\(source.id):SOURCE_NOT_READABLE",
            code: "SOURCE_NOT_READABLE",
            severity: .blocking,
            sourceID: source.id,
            summary: "The source cannot be read with the current user permissions.",
            affectedURL: source.rootURL
          )
        ]
      )
    }

    guard let adapter = registry.adapter(for: source.providerID) else {
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [
          InventoryIssue(
            id: "\(source.id):ADAPTER_NOT_FOUND",
            code: "ADAPTER_NOT_FOUND",
            severity: .blocking,
            sourceID: source.id,
            summary: "No storage adapter is registered for this source."
          )
        ]
      )
    }

    return await adapter.scan(source: source)
  }

  public func scan(sources: [ScanSource]) async -> InventorySnapshot {
    var installations: [ModelInstallation] = []
    var issues: [InventoryIssue] = []
    var scannedSourceIDs: Set<ScanSource.ID> = []

    for source in sources where source.isEnabled {
      let result = await scan(source: source)
      installations.append(contentsOf: result.installations)
      issues.append(contentsOf: result.issues)
      scannedSourceIDs.insert(source.id)
    }

    return InventorySnapshot(
      installations: installations,
      issues: issues,
      scannedSourceIDs: scannedSourceIDs
    )
  }
}
