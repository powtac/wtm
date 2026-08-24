import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct ManualFolderAdapter: StorageProviderAdapter {
  public let id = ProviderID.manual
  public let displayName = "Manual Folder"

  public init() {}

  public func scan(source: ScanSource) async -> AdapterScanResult {
    let entries: [FileSystemEntry]
    do {
      entries = try ReadOnlyDirectoryWalker().entries(under: source.rootURL)
    } catch {
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [scanIssue(source: source, code: "MANUAL_ENUMERATION_FAILED", url: source.rootURL)]
      )
    }

    let regularFiles = entries.filter { $0.isRegularFile || $0.isSymbolicLink }
    let ggufFiles = regularFiles.filter { $0.url.pathExtension.lowercased() == "gguf" }
    let partialFiles = regularFiles.filter { $0.url.pathExtension.lowercased() == "incomplete" }
    let safetensorFiles = regularFiles.filter {
      $0.url.pathExtension.lowercased() == "safetensors"
    }

    var installations = ggufFiles.compactMap { installation(forGGUF: $0, source: source) }
    let safetensorGroups = Dictionary(grouping: safetensorFiles) {
      $0.url.deletingLastPathComponent()
    }
    installations.append(
      contentsOf: safetensorGroups.compactMap { directory, files in
        installation(
          forSafetensors: files, directory: directory, allFiles: regularFiles, source: source)
      }
    )
    installations.append(
      contentsOf: partialFiles.compactMap { partialInstallation($0, source: source) })

    return AdapterScanResult(source: source, installations: installations)
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
    let configurations = relatedFiles.map(\.url).filter { $0.lastPathComponent == "config.json" }
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
      timestamps: timestamps(for: directory)
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
    if let creationDate = metadata.creationDate {
      return [
        ObservedTimestamp(
          value: creationDate,
          kind: .fileCreation,
          confidence: .derived
        )
      ]
    }
    if let modificationDate = metadata.modificationDate {
      return [
        ObservedTimestamp(
          value: modificationDate,
          kind: .fileModification,
          confidence: .heuristic
        )
      ]
    }
    return []
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
