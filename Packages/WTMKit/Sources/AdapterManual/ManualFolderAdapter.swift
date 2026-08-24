import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct ManualFolderAdapter: StorageProviderAdapter {
  private static let streamBatchSize = 25

  public let id = ProviderID.manual
  public let displayName = "Manual Folder"

  public init() {}

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
        var regularFilesByDirectory: [URL: [FileSystemEntry]] = [:]
        var safetensorFilesByDirectory: [URL: [FileSystemEntry]] = [:]

        func yieldPendingIfNeeded(force: Bool = false) {
          guard !pendingInstallations.isEmpty else { return }
          guard force || pendingInstallations.count >= Self.streamBatchSize else { return }
          continuation.yield(AdapterScanBatch(installations: pendingInstallations))
          pendingInstallations.removeAll(keepingCapacity: true)
        }

        do {
          for try await entry in ReadOnlyDirectoryWalker().entryStream(under: source.rootURL) {
            guard !Task.isCancelled else {
              continuation.finish()
              return
            }
            guard entry.isRegularFile || entry.isSymbolicLink else { continue }

            let directory = entry.url.deletingLastPathComponent()
            regularFilesByDirectory[directory, default: []].append(entry)
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
              safetensorFilesByDirectory[directory, default: []].append(entry)
            default:
              break
            }
          }

          yieldPendingIfNeeded(force: true)
          for directory in safetensorFilesByDirectory.keys.sorted(by: { $0.path < $1.path }) {
            guard !Task.isCancelled else {
              continuation.finish()
              return
            }
            guard
              let safetensorFiles = safetensorFilesByDirectory[directory],
              let allFiles = regularFilesByDirectory[directory],
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
}
