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

public enum InventoryScanEvent: Sendable {
  case started(sourceCount: Int, startedAt: Date)
  case sourceStarted(source: ScanSource, index: Int, total: Int)
  case batch(
    sourceID: ScanSource.ID,
    installations: [ModelInstallation],
    issues: [InventoryIssue]
  )
  case sourceFinished(sourceID: ScanSource.ID, completed: Int, total: Int)
  case finished(scannedSourceIDs: Set<ScanSource.ID>, scannedAt: Date)
}

/// Coordinates Phase-1 storage adapters without exposing actions or process execution.
public actor InventoryCoordinator {
  private let registry: AdapterRegistry
  private let installationBatchSize: Int
  private let reconciler = InstallationReconciler()

  public init(registry: AdapterRegistry, installationBatchSize: Int = 50) {
    self.registry = registry
    self.installationBatchSize = max(1, installationBatchSize)
  }

  /// Streams deterministic, bounded updates while retaining a single scan implementation.
  public nonisolated func scanEvents(sources: [ScanSource]) -> AsyncStream<InventoryScanEvent> {
    AsyncStream { continuation in
      let task = Task {
        await runScan(sources: sources, continuation: continuation)
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func scan(source: ScanSource) async -> AdapterScanResult {
    guard source.isEnabled else {
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

    if source.accessState == .offline {
      return rejectedSource(source, code: "SOURCE_OFFLINE", summary: "The source is offline.")
    }
    if source.accessState == .denied {
      return rejectedSource(
        source,
        code: "SOURCE_NOT_READABLE",
        summary: "The source cannot be read with the current user permissions."
      )
    }
    if source.accessState == .stale {
      return rejectedSource(
        source,
        code: "SOURCE_ACCESS_STALE",
        summary: "The saved source access must be granted again."
      )
    }
    guard source.accessState == .allowed || source.accessState == .limited else {
      return rejectedSource(
        source,
        code: "SOURCE_NOT_ALLOWED",
        summary: "The source is not enabled and allowed."
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

  private func rejectedSource(
    _ source: ScanSource,
    code: String,
    summary: String
  ) -> AdapterScanResult {
    AdapterScanResult(
      source: source,
      installations: [],
      issues: [
        InventoryIssue(
          id: "\(source.id):\(code)",
          code: code,
          severity: .warning,
          sourceID: source.id,
          summary: summary,
          affectedURL: source.rootURL
        )
      ]
    )
  }

  public func scan(sources: [ScanSource]) async -> InventorySnapshot {
    var installations: [ModelInstallation] = []
    var issues: [InventoryIssue] = []
    var scannedSourceIDs: Set<ScanSource.ID> = []

    for source in orderedEnabledSources(sources) {
      let result = await scan(source: source)
      installations = reconciler.reconcile(installations + result.installations)
      issues.append(contentsOf: result.issues)
      scannedSourceIDs.insert(source.id)
    }

    return InventorySnapshot(
      installations: installations,
      issues: issues,
      scannedSourceIDs: scannedSourceIDs
    )
  }

  private func runScan(
    sources: [ScanSource],
    continuation: AsyncStream<InventoryScanEvent>.Continuation
  ) async {
    let enabledSources = orderedEnabledSources(sources)
    let startedAt = Date.now
    var scannedSourceIDs: Set<ScanSource.ID> = []
    var canonicalInstallations: [ModelInstallation] = []
    continuation.yield(.started(sourceCount: enabledSources.count, startedAt: startedAt))

    for (offset, source) in enabledSources.enumerated() {
      guard !Task.isCancelled else {
        continuation.finish()
        return
      }

      continuation.yield(
        .sourceStarted(source: source, index: offset + 1, total: enabledSources.count)
      )
      for await adapterBatch in adapterBatchStream(for: source) {
        guard !Task.isCancelled else {
          continuation.finish()
          return
        }

        let previousIDs = Set(canonicalInstallations.map(\.id))
        canonicalInstallations = reconciler.reconcile(
          canonicalInstallations + adapterBatch.installations
        )
        let acceptedInstallations = canonicalInstallations.filter { installation in
          !previousIDs.contains(installation.id)
            && adapterBatch.installations.contains(where: { $0.id == installation.id })
        }
        let batches = acceptedInstallations.chunked(maximumCount: installationBatchSize)
        if batches.isEmpty {
          continuation.yield(
            .batch(sourceID: source.id, installations: [], issues: adapterBatch.issues)
          )
        } else {
          for (batchIndex, batch) in batches.enumerated() {
            guard !Task.isCancelled else {
              continuation.finish()
              return
            }
            continuation.yield(
              .batch(
                sourceID: source.id,
                installations: batch,
                issues: batchIndex == 0 ? adapterBatch.issues : []
              )
            )
          }
        }
      }

      scannedSourceIDs.insert(source.id)
      continuation.yield(
        .sourceFinished(
          sourceID: source.id,
          completed: offset + 1,
          total: enabledSources.count
        )
      )
    }

    guard !Task.isCancelled else {
      continuation.finish()
      return
    }
    continuation.yield(.finished(scannedSourceIDs: scannedSourceIDs, scannedAt: .now))
    continuation.finish()
  }

  private func adapterBatchStream(for source: ScanSource) -> AsyncStream<AdapterScanBatch> {
    if source.isEnabled,
      source.accessState == .allowed || source.accessState == .limited,
      FileManager.default.fileExists(atPath: source.rootURL.path),
      FileManager.default.isReadableFile(atPath: source.rootURL.path),
      let adapter = registry.adapter(for: source.providerID)
    {
      return adapter.scanBatches(source: source)
    }

    return AsyncStream { continuation in
      let task = Task {
        let result = await self.scan(source: source)
        continuation.yield(
          AdapterScanBatch(installations: result.installations, issues: result.issues)
        )
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private nonisolated func orderedEnabledSources(_ sources: [ScanSource]) -> [ScanSource] {
    sources.enumerated()
      .filter { $0.element.isEnabled }
      .sorted { left, right in
        let leftPriority = left.element.providerID == .manual ? 1 : 0
        let rightPriority = right.element.providerID == .manual ? 1 : 0
        if leftPriority != rightPriority { return leftPriority < rightPriority }
        return left.offset < right.offset
      }
      .map(\.element)
  }
}

private extension Array {
  func chunked(maximumCount: Int) -> [[Element]] {
    guard !isEmpty else { return [] }
    return stride(from: startIndex, to: endIndex, by: maximumCount).map { start in
      let end = Swift.min(start + maximumCount, endIndex)
      return Array(self[start..<end])
    }
  }
}
