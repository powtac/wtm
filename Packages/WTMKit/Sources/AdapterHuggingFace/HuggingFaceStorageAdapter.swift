import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

/// Fail-closed validation errors for data-driven Hugging Face repository aliases.
public enum HuggingFaceRepositoryAliasError: Error, Equatable, Sendable {
  case invalidAliasKey(String)
  case invalidRepositoryID(String)
  case normalizedKeyCollision(String)
}

public struct HuggingFaceStorageAdapter: StorageProviderAdapter {
  public static let builtInRepositoryAliases = [
    "gpt-oss-20b": "openai/gpt-oss-20b"
  ]

  public let id = ProviderID.huggingFace
  public let displayName = "Hugging Face"
  private let repositoryAliases: [String: String]

  private struct ConfirmedRepository {
    let id: String
    let evidence: String
  }

  public init() throws {
    try self.init(repositoryAliases: Self.builtInRepositoryAliases)
  }

  public init(repositoryAliases: [String: String]) throws {
    var validatedAliases: [String: String] = [:]
    for key in repositoryAliases.keys.sorted() {
      guard Self.isValidRepositoryComponent(key) else {
        throw HuggingFaceRepositoryAliasError.invalidAliasKey(key)
      }
      let normalizedKey = key.lowercased()
      guard validatedAliases[normalizedKey] == nil else {
        throw HuggingFaceRepositoryAliasError.normalizedKeyCollision(normalizedKey)
      }
      guard let repositoryID = repositoryAliases[key], Self.isValidRepositoryID(repositoryID)
      else {
        throw HuggingFaceRepositoryAliasError.invalidRepositoryID(repositoryAliases[key] ?? "")
      }
      validatedAliases[normalizedKey] = repositoryID
    }
    self.repositoryAliases = validatedAliases
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
        let repositories: [URL]
        do {
          guard let rootIdentity = source.rootIdentity else {
            throw ScopedPathError.sourceIdentityUnavailable
          }
          let policy = ScopedPathPolicy(
            rootURL: source.rootURL,
            volumeIdentity: source.volumeIdentity,
            expectedRootIdentity: rootIdentity
          )
          try policy.revalidateRoot()
          repositories = try FileManager.default.contentsOfDirectory(
            at: source.rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
          ).filter { url in
            url.lastPathComponent.hasPrefix("models--")
              && ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
          }
          try policy.revalidateRoot()
        } catch {
          continuation.yield(
            AdapterScanBatch(
              installations: [],
              issues: [
                issue(
                  source: source,
                  code: "HF_CACHE_ENUMERATION_FAILED",
                  url: source.rootURL
                )
              ]
            )
          )
          continuation.finish()
          return
        }

        for repositoryURL in repositories {
          guard !Task.isCancelled else {
            continuation.finish()
            return
          }
          var repositoryIssues: [InventoryIssue] = []
          do {
            let installations = try scanRepository(
              repositoryURL,
              source: source,
              issues: &repositoryIssues
            )
            continuation.yield(
              AdapterScanBatch(installations: installations, issues: repositoryIssues)
            )
          } catch {
            continuation.yield(
              AdapterScanBatch(
                installations: [],
                issues: [
                  issue(source: source, code: "HF_REPOSITORY_INVALID", url: repositoryURL)
                ]
              )
            )
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func scanRepository(
    _ repositoryURL: URL,
    source: ScanSource,
    issues: inout [InventoryIssue]
  ) throws -> [ModelInstallation] {
    let entries = try ReadOnlyDirectoryWalker().entries(under: repositoryURL, approvedBy: source)
    let cacheRepositoryName = repositoryURL.lastPathComponent
      .dropFirst("models--".count)
      .replacingOccurrences(of: "--", with: "/")
    guard !cacheRepositoryName.isEmpty else { return [] }
    let repository = confirmedRepository(for: cacheRepositoryName)

    let snapshotRoot = repositoryURL.appending(path: "snapshots", directoryHint: .isDirectory)
    let snapshotPrefix = snapshotRoot.path + "/"
    let snapshotFiles = entries.filter { entry in
      guard (entry.isRegularFile || entry.isSymbolicLink),
        entry.url.path.hasPrefix(snapshotPrefix),
        entry.url.lastPathComponent != ".DS_Store"
      else { return false }

      let relativeComponents = entry.url.path.dropFirst(snapshotPrefix.count).split(separator: "/")
      return relativeComponents.count >= 2 && !relativeComponents[0].hasPrefix(".")
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
        cacheRepositoryName: cacheRepositoryName,
        repository: repository,
        revision: revision,
        files: files,
        partialEntries: partialEntries,
        physicalCounts: physicalCounts,
        source: source
      )
    }

    if groupedByRevision.isEmpty, !partialEntries.isEmpty,
      let incomplete = makeIncompleteInstallation(
        cacheRepositoryName: cacheRepositoryName,
        repository: repository,
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
    cacheRepositoryName: String,
    repository: ConfirmedRepository?,
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

    let logicalRepositoryName = repository?.id ?? cacheRepositoryName
    let identityID = "hf:\(logicalRepositoryName.lowercased())"
    let variantID = "\(identityID):\(revision)"
    let identity = ModelIdentity(
      id: identityID,
      displayName: logicalRepositoryName.split(separator: "/").last.map(String.init)
        ?? logicalRepositoryName,
      family: repository?.id
    )
    let format = inferredFormat(from: files.map(\.url))
    let variant = ModelVariant(id: variantID, identityID: identityID, format: format)
    let configurations = files.map(\.url).filter { isConfiguration($0) }
    return ModelInstallation(
      id: "\(source.id):\(logicalRepositoryName):\(revision)",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: files.first?.url.deletingLastPathComponent() ?? source.rootURL,
      state: partialEntries.isEmpty ? .stored : .incomplete,
      artifacts: artifacts,
      configurationURLs: configurations,
      timestamps: timestamps(in: files),
      modelCard: repository.flatMap(modelCard)
    )
  }

  private func makeIncompleteInstallation(
    cacheRepositoryName: String,
    repository: ConfirmedRepository?,
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

    let logicalRepositoryName = repository?.id ?? cacheRepositoryName
    let identityID = "hf:\(logicalRepositoryName.lowercased())"
    let variantID = "\(identityID):incomplete"
    let identity = ModelIdentity(
      id: identityID,
      displayName: logicalRepositoryName.split(separator: "/").last.map(String.init)
        ?? logicalRepositoryName,
      family: repository?.id
    )
    let variant = ModelVariant(id: variantID, identityID: identityID, format: .unknown)
    return ModelInstallation(
      id: "\(source.id):\(logicalRepositoryName):incomplete",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: firstPartialEntry.url,
      state: .incomplete,
      artifacts: artifacts,
      timestamps: timestamps(in: partialEntries),
      modelCard: repository.flatMap(modelCard)
    )
  }

  private func confirmedRepository(for cacheRepositoryName: String) -> ConfirmedRepository? {
    let alias = repositoryAliases[cacheRepositoryName.lowercased()]
    let candidate = alias ?? cacheRepositoryName
    guard Self.isValidRepositoryID(candidate) else { return nil }
    return ConfirmedRepository(
      id: candidate,
      evidence: alias == nil
        ? "Hugging Face cache key"
        : "WTM Hugging Face repository alias"
    )
  }

  private static func isValidRepositoryID(_ repositoryID: String) -> Bool {
    let components = repositoryID.split(separator: "/", omittingEmptySubsequences: false)
    return components.count == 2
      && components.allSatisfy { component in
        isValidRepositoryComponent(String(component))
      }
  }

  private static func isValidRepositoryComponent(_ component: String) -> Bool {
    guard !component.isEmpty, component != ".", component != ".." else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    return component.unicodeScalars.allSatisfy(allowed.contains)
  }

  private func modelCard(for repository: ConfirmedRepository) -> ModelCardLink? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "huggingface.co"
    components.path = "/\(repository.id)"
    guard let url = components.url else { return nil }
    return ModelCardLink(url: url, confidence: .confirmed, evidence: repository.evidence)
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
    ConfigurationFilePolicy().isAllowed(url)
  }

  private func timestamps(in entries: [FileSystemEntry]) -> [ObservedTimestamp] {
    let metadata = entries.compactMap { entry in
      try? FileMetadataReader().metadata(for: entry.resolvedURL)
    }
    var timestamps: [ObservedTimestamp] = []
    if let oldestCreation = metadata.compactMap(\.creationDate).min() {
      timestamps.append(
        ObservedTimestamp(value: oldestCreation, kind: .fileCreation, confidence: .derived)
      )
    }
    if let oldestModification = metadata.compactMap(\.modificationDate).min() {
      timestamps.append(
        ObservedTimestamp(
          value: oldestModification,
          kind: .fileModification,
          confidence: .heuristic
        )
      )
    }
    return timestamps
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
