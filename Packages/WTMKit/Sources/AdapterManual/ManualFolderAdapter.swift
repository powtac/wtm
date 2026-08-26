import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct ManualScanBudget: Sendable {
  public let maximumEntryCount: Int
  public let maximumSafetensorDirectoryCount: Int
  public let maximumEntriesPerSafetensorDirectory: Int
  public let maximumDuration: Duration

  public init(
    maximumEntryCount: Int = 250_000,
    maximumSafetensorDirectoryCount: Int = 10_000,
    maximumEntriesPerSafetensorDirectory: Int = 10_000,
    maximumDuration: Duration = .seconds(300)
  ) {
    self.maximumEntryCount = max(maximumEntryCount, 1)
    self.maximumSafetensorDirectoryCount = max(maximumSafetensorDirectoryCount, 1)
    self.maximumEntriesPerSafetensorDirectory = max(maximumEntriesPerSafetensorDirectory, 1)
    self.maximumDuration = maximumDuration
  }
}

public struct ManualFolderAdapter: StorageProviderAdapter {
  private static let streamBatchSize = 25

  public let id = ProviderID.manual
  public let displayName = "Manual Folder"
  private let budget: ManualScanBudget

  public init(budget: ManualScanBudget = ManualScanBudget()) {
    self.budget = budget
  }

  public func scan(source: ScanSource) async -> AdapterScanResult {
    var installations: [ModelInstallation] = []
    var issues: [InventoryIssue] = []
    for await batch in scanBatches(source: source) {
      installations.append(contentsOf: batch.installations)
      issues.append(contentsOf: batch.issues)
    }
    return AdapterScanResult(source: source, installations: installations, issues: issues)
  }

  public func scanBatches(source: ScanSource) -> AsyncStream<AdapterScanBatch> {
    AsyncStream { continuation in
      let task = Task {
        var pendingInstallations: [ModelInstallation] = []
        var safetensorDirectories: Set<URL> = []
        var scannedEntryCount = 0
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget.maximumDuration)
        var scanWasTruncated = false

        func yieldPendingIfNeeded(force: Bool = false) {
          guard !pendingInstallations.isEmpty else { return }
          guard force || pendingInstallations.count >= Self.streamBatchSize else { return }
          continuation.yield(AdapterScanBatch(installations: pendingInstallations))
          pendingInstallations.removeAll(keepingCapacity: true)
        }

        do {
          try ReadOnlyDirectoryWalker().visitEntries(
            under: source.rootURL,
            approvedBy: source
          ) { entry in
            guard !Task.isCancelled else {
              return false
            }
            scannedEntryCount += 1
            if scannedEntryCount > budget.maximumEntryCount || clock.now >= deadline {
              scanWasTruncated = true
              return false
            }
            guard entry.isRegularFile || entry.isSymbolicLink else { return true }

            let directory = entry.url.deletingLastPathComponent()
            switch entry.url.pathExtension.lowercased() {
            case "gguf":
              if let installation = installation(forGGUF: entry, source: source) {
                pendingInstallations.append(installation)
                yieldPendingIfNeeded()
              }
            case "incomplete":
              if let installation = partialInstallation(entry, source: source) {
                pendingInstallations.append(installation)
                yieldPendingIfNeeded()
              }
            case "safetensors":
              if safetensorDirectories.count >= budget.maximumSafetensorDirectoryCount,
                !safetensorDirectories.contains(directory)
              {
                scanWasTruncated = true
                return false
              }
              safetensorDirectories.insert(directory)
            default:
              break
            }
            return true
          }

          guard !Task.isCancelled else {
            continuation.finish()
            return
          }

          yieldPendingIfNeeded(force: true)
          if scanWasTruncated {
            continuation.yield(
              AdapterScanBatch(installations: [], issues: [scanBudgetIssue(source: source)])
            )
            continuation.finish()
            return
          }
          for directory in safetensorDirectories.sorted(by: { $0.path < $1.path }) {
            guard !Task.isCancelled else {
              continuation.finish()
              return
            }
            var allFiles: [FileSystemEntry] = []
            try ReadOnlyDirectoryWalker().visitEntries(
              under: directory,
              approvedBy: source,
              descendIntoSubdirectories: false
            ) { entry in
              guard entry.isRegularFile || entry.isSymbolicLink else { return true }
              if allFiles.count >= budget.maximumEntriesPerSafetensorDirectory
                || clock.now >= deadline
              {
                scanWasTruncated = true
                return false
              }
              allFiles.append(entry)
              return true
            }
            if scanWasTruncated { break }
            let safetensorFiles = allFiles.filter {
              $0.url.pathExtension.lowercased() == "safetensors"
            }
            guard !safetensorFiles.isEmpty,
              let installation = installation(
                forSafetensors: safetensorFiles,
                directory: directory,
                allFiles: allFiles,
                source: source
              )
            else { continue }
            pendingInstallations.append(installation)
            yieldPendingIfNeeded()
          }
          yieldPendingIfNeeded(force: true)
          if scanWasTruncated {
            continuation.yield(
              AdapterScanBatch(installations: [], issues: [scanBudgetIssue(source: source)])
            )
          }
        } catch {
          yieldPendingIfNeeded(force: true)
          continuation.yield(
            AdapterScanBatch(
              installations: [],
              issues: [
                scanIssue(
                  source: source,
                  code: "MANUAL_ENUMERATION_FAILED",
                  url: source.rootURL
                )
              ]
            )
          )
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func installation(forGGUF entry: FileSystemEntry, source: ScanSource)
    -> ModelInstallation?
  {
    guard let artifact = artifact(for: entry.url, kind: .weights) else { return nil }
    let name = entry.url.deletingPathExtension().lastPathComponent
    let identityID = "manual:\(name.lowercased())"
    let variantID = "\(identityID):gguf"
    let identity = ModelIdentity(id: identityID, displayName: name)
    let variant = ModelVariant(
      id: variantID,
      identityID: identityID,
      format: .gguf,
      quantization: quantization(from: name)
    )
    return ModelInstallation(
      id: "\(source.id):\(entry.url.path)",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: entry.url,
      state: .stored,
      artifacts: [artifact],
      timestamps: timestamps(for: entry.url)
    )
  }

  private func installation(
    forSafetensors entries: [FileSystemEntry],
    directory: URL,
    allFiles: [FileSystemEntry],
    source: ScanSource
  ) -> ModelInstallation? {
    let relatedFiles = allFiles.filter { $0.url.deletingLastPathComponent() == directory }
    let artifacts = relatedFiles.compactMap { entry in
      artifact(for: entry.url, kind: artifactKind(for: entry.url))
    }
    guard !artifacts.isEmpty else { return nil }

    let name = directory.lastPathComponent
    let identityID = "manual:\(name.lowercased())"
    let variantID = "\(identityID):safetensors"
    let identity = ModelIdentity(id: identityID, displayName: name)
    let variant = ModelVariant(id: variantID, identityID: identityID, format: .safetensors)
    let configurations = relatedFiles.map(\.url).filter(ConfigurationFilePolicy().isAllowed)
    return ModelInstallation(
      id: "\(source.id):\(directory.path)",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: directory,
      state: .stored,
      artifacts: artifacts,
      configurationURLs: configurations,
      timestamps: timestamps(in: relatedFiles)
    )
  }

  private func partialInstallation(
    _ entry: FileSystemEntry,
    source: ScanSource
  ) -> ModelInstallation? {
    guard let artifact = artifact(for: entry.url, kind: .weights, isPartial: true) else {
      return nil
    }
    let name = entry.url.deletingPathExtension().lastPathComponent
    let identityID = "manual:\(name.lowercased())"
    let variantID = "\(identityID):partial"
    let identity = ModelIdentity(id: identityID, displayName: name)
    let variant = ModelVariant(id: variantID, identityID: identityID, format: .unknown)
    return ModelInstallation(
      id: "\(source.id):\(entry.url.path):partial",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: entry.url,
      state: .incomplete,
      artifacts: [artifact],
      timestamps: timestamps(for: entry.url)
    )
  }

  private func artifact(
    for url: URL,
    kind: ArtifactKind,
    isPartial: Bool = false
  ) -> Artifact? {
    guard let metadata = try? FileMetadataReader().metadata(for: url) else { return nil }
    return Artifact(
      id: "manual:\(url.path)",
      url: url,
      kind: kind,
      logicalByteCount: metadata.logicalByteCount,
      allocatedByteCount: metadata.allocatedByteCount,
      physicalIdentifier: metadata.physicalIdentifier,
      isPartial: isPartial
    )
  }

  private func artifactKind(for url: URL) -> ArtifactKind {
    switch url.lastPathComponent.lowercased() {
    case "config.json": .configuration
    case let name where name.contains("tokenizer"): .tokenizer
    default: url.pathExtension.lowercased() == "safetensors" ? .weights : .metadata
    }
  }

  private func quantization(from name: String) -> String? {
    let pattern = #"(?i)(Q[2-8](?:_[A-Z0-9]+)*)"#
    guard let range = name.range(of: pattern, options: .regularExpression) else { return nil }
    return String(name[range]).uppercased()
  }

  private func timestamps(for url: URL) -> [ObservedTimestamp] {
    guard let metadata = try? FileMetadataReader().metadata(for: url) else { return [] }
    return timestamps(from: [metadata])
  }

  private func timestamps(in entries: [FileSystemEntry]) -> [ObservedTimestamp] {
    timestamps(
      from: entries.compactMap { try? FileMetadataReader().metadata(for: $0.resolvedURL) }
    )
  }

  private func timestamps(from metadata: [FileMetadata]) -> [ObservedTimestamp] {
    var timestamps: [ObservedTimestamp] = []
    if let creationDate = metadata.compactMap(\.creationDate).min() {
      timestamps.append(
        ObservedTimestamp(
          value: creationDate,
          kind: .fileCreation,
          confidence: .derived
        )
      )
    }
    if let modificationDate = metadata.compactMap(\.modificationDate).min() {
      timestamps.append(
        ObservedTimestamp(
          value: modificationDate,
          kind: .fileModification,
          confidence: .heuristic
        )
      )
    }
    return timestamps
  }

  private func scanIssue(source: ScanSource, code: String, url: URL) -> InventoryIssue {
    InventoryIssue(
      id: "\(source.id):\(code)",
      code: code,
      severity: .error,
      sourceID: source.id,
      summary: "The selected folder could not be inventoried.",
      affectedURL: url
    )
  }

  private func scanBudgetIssue(source: ScanSource) -> InventoryIssue {
    InventoryIssue(
      id: "\(source.id):MANUAL_SCAN_TRUNCATED",
      code: "MANUAL_SCAN_TRUNCATED",
      severity: .warning,
      sourceID: source.id,
      summary:
        "The scan reached its safety budget. Results are incomplete; narrow the source folder.",
      affectedURL: source.rootURL
    )
  }
}
