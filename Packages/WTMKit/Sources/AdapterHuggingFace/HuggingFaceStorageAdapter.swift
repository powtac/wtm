import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct HuggingFaceStorageAdapter: StorageProviderAdapter {
  public let id = ProviderID.huggingFace
  public let displayName = "Hugging Face"

  public init() {}

  public func scan(source: ScanSource) async -> AdapterScanResult {
    let repositories: [URL]
    do {
      repositories = try FileManager.default.contentsOfDirectory(
        at: source.rootURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      ).filter { url in
        url.lastPathComponent.hasPrefix("models--")
          && ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
      }
    } catch {
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [issue(source: source, code: "HF_CACHE_ENUMERATION_FAILED", url: source.rootURL)]
      )
    }

    var installations: [ModelInstallation] = []
    var issues: [InventoryIssue] = []
    for repositoryURL in repositories {
      do {
        installations.append(
          contentsOf: try scanRepository(repositoryURL, source: source, issues: &issues)
        )
      } catch {
        issues.append(issue(source: source, code: "HF_REPOSITORY_INVALID", url: repositoryURL))
      }
    }
    return AdapterScanResult(source: source, installations: installations, issues: issues)
  }

  private func scanRepository(
    _ repositoryURL: URL,
    source: ScanSource,
    issues: inout [InventoryIssue]
  ) throws -> [ModelInstallation] {
    let entries = try ReadOnlyDirectoryWalker().entries(under: repositoryURL)
    let repositoryName = repositoryURL.lastPathComponent
      .dropFirst("models--".count)
      .replacingOccurrences(of: "--", with: "/")
    guard !repositoryName.isEmpty else { return [] }

    let snapshotRoot = repositoryURL.appending(path: "snapshots", directoryHint: .isDirectory)
    let snapshotPrefix = snapshotRoot.path + "/"
    let snapshotFiles = entries.filter {
      ($0.isRegularFile || $0.isSymbolicLink) && $0.url.path.hasPrefix(snapshotPrefix)
    }
    let groupedByRevision = Dictionary(grouping: snapshotFiles) { entry in
      let remainder = entry.url.path.dropFirst(snapshotPrefix.count)
      return remainder.split(separator: "/").first.map(String.init) ?? "unknown"
    }
    let partialEntries = entries.filter {
      ($0.isRegularFile || $0.isSymbolicLink)
        && $0.url.lastPathComponent.hasSuffix(".incomplete")
    }

    var physicalCounts: [String: Int] = [:]
    for entry in snapshotFiles {
      if let metadata = try? FileMetadataReader().metadata(for: entry.resolvedURL),
        let identifier = metadata.physicalIdentifier
      {
        physicalCounts[identifier, default: 0] += 1
      }
    }

    var result = groupedByRevision.compactMap { revision, files in
      makeInstallation(
        repositoryName: repositoryName,
        revision: revision,
        files: files,
        partialEntries: partialEntries,
        physicalCounts: physicalCounts,
        source: source
      )
    }

    if groupedByRevision.isEmpty, !partialEntries.isEmpty,
      let incomplete = makeIncompleteInstallation(
        repositoryName: repositoryName,
        partialEntries: partialEntries,
        source: source
      )
    {
      result.append(incomplete)
    }

    if !partialEntries.isEmpty {
      issues.append(issue(source: source, code: "HF_DOWNLOAD_INCOMPLETE", url: repositoryURL))
    }
    return result
  }

  private func makeInstallation(
    repositoryName: String,
    revision: String,
    files: [FileSystemEntry],
    partialEntries: [FileSystemEntry],
    physicalCounts: [String: Int],
    source: ScanSource
  ) -> ModelInstallation? {
    let artifacts = files.compactMap { entry -> Artifact? in
      guard let metadata = try? FileMetadataReader().metadata(for: entry.resolvedURL) else {
        return nil
      }
      return Artifact(
        id: "hf:\(entry.url.path)",
        url: entry.url,
        kind: artifactKind(for: entry.url),
        logicalByteCount: metadata.logicalByteCount,
        allocatedByteCount: metadata.allocatedByteCount,
        physicalIdentifier: metadata.physicalIdentifier,
        isShared: metadata.physicalIdentifier.map { (physicalCounts[$0] ?? 0) > 1 } ?? false
      )
    }
    guard !artifacts.isEmpty else { return nil }

    let identityID = "hf:\(repositoryName.lowercased())"
    let variantID = "\(identityID):\(revision)"
    let identity = ModelIdentity(
      id: identityID,
      displayName: repositoryName.split(separator: "/").last.map(String.init) ?? repositoryName,
      family: repositoryName
    )
    let format = inferredFormat(from: files.map(\.url))
    let variant = ModelVariant(id: variantID, identityID: identityID, format: format)
    let configurations = files.map(\.url).filter { isConfiguration($0) }
    return ModelInstallation(
      id: "\(source.id):\(repositoryName):\(revision)",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: files.first?.url.deletingLastPathComponent() ?? source.rootURL,
      state: partialEntries.isEmpty ? .stored : .incomplete,
      artifacts: artifacts,
      configurationURLs: configurations,
      timestamps: oldestTimestamp(in: files),
      modelCard: modelCard(for: repositoryName)
    )
  }

  private func makeIncompleteInstallation(
    repositoryName: String,
    partialEntries: [FileSystemEntry],
    source: ScanSource
  ) -> ModelInstallation? {
    guard let firstPartialEntry = partialEntries.first else { return nil }
    let artifacts = partialEntries.compactMap { entry -> Artifact? in
      guard let metadata = try? FileMetadataReader().metadata(for: entry.resolvedURL) else {
        return nil
      }
      return Artifact(
        id: "hf:\(entry.url.path)",
        url: entry.url,
        kind: .weights,
        logicalByteCount: metadata.logicalByteCount,
        allocatedByteCount: metadata.allocatedByteCount,
        physicalIdentifier: metadata.physicalIdentifier,
        isPartial: true
      )
    }
    guard !artifacts.isEmpty else { return nil }

    let identityID = "hf:\(repositoryName.lowercased())"
    let variantID = "\(identityID):incomplete"
    let identity = ModelIdentity(id: identityID, displayName: repositoryName)
    let variant = ModelVariant(id: variantID, identityID: identityID, format: .unknown)
    return ModelInstallation(
      id: "\(source.id):\(repositoryName):incomplete",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: firstPartialEntry.url,
      state: .incomplete,
      artifacts: artifacts,
      timestamps: oldestTimestamp(in: partialEntries),
      modelCard: modelCard(for: repositoryName)
    )
  }

  private func modelCard(for repositoryName: String) -> ModelCardLink? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "huggingface.co"
    components.path = "/\(repositoryName)"
    guard let url = components.url else { return nil }
    return ModelCardLink(url: url, confidence: .confirmed, evidence: "Hugging Face cache key")
  }

  private func inferredFormat(from urls: [URL]) -> ModelFormat {
    if urls.contains(where: { $0.pathExtension.lowercased() == "gguf" }) { return .gguf }
    if urls.contains(where: { $0.pathExtension.lowercased() == "safetensors" }) {
      return .safetensors
    }
    return .unknown
  }

  private func artifactKind(for url: URL) -> ArtifactKind {
    let name = url.lastPathComponent.lowercased()
    if ["gguf", "safetensors", "bin"].contains(url.pathExtension.lowercased()) {
      return .weights
    }
    if name == "config.json" || name.hasSuffix(".json") { return .configuration }
    if name.contains("tokenizer") { return .tokenizer }
    return .metadata
  }

  private func isConfiguration(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    return name == "config.json" || name == "generation_config.json"
  }

  private func oldestTimestamp(in entries: [FileSystemEntry]) -> [ObservedTimestamp] {
    let dates = entries.compactMap { entry in
      try? FileMetadataReader().metadata(for: entry.resolvedURL).creationDate
    }
    guard let oldest = dates.compactMap({ $0 }).min() else { return [] }
    return [ObservedTimestamp(value: oldest, kind: .fileCreation, confidence: .derived)]
  }

  private func issue(source: ScanSource, code: String, url: URL) -> InventoryIssue {
    InventoryIssue(
      id: "\(source.id):\(code):\(url.path)",
      code: code,
      severity: .warning,
      sourceID: source.id,
      summary: "Hugging Face cache data is incomplete or invalid.",
      affectedURL: url
    )
  }
}
