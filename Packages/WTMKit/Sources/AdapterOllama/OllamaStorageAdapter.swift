import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct OllamaStorageAdapter: StorageProviderAdapter {
  private static let maximumManifestDescriptorCount = 100_000

  public let id = ProviderID.ollama
  public let displayName = "Ollama"

  public init() {}

  public func scan(source: ScanSource) async -> AdapterScanResult {
    let entries: [FileSystemEntry]
    do {
      entries = try ReadOnlyDirectoryWalker().entries(under: source.rootURL, approvedBy: source)
    } catch {
      let code: String
      if let walkerError = error as? DirectoryWalkerError,
        walkerError == .budgetExceeded
      {
        code = "OLLAMA_SCAN_TRUNCATED"
      } else {
        code = "OLLAMA_ENUMERATION_FAILED"
      }
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [issue(source: source, code: code, url: source.rootURL)]
      )
    }

    let manifestEntries = entries.filter {
      ($0.isRegularFile || $0.isSymbolicLink) && $0.url.path.contains("/manifests/")
    }
    let partialBlobEntries = entries.filter { entry in
      guard entry.isRegularFile || entry.isSymbolicLink,
        isPartialBlob(entry.resolvedURL, root: source.rootURL)
      else { return false }
      return true
    }
    var parsedManifests: [ParsedManifest] = []
    var issues: [InventoryIssue] = []

    for entry in manifestEntries {
      let manifestURL = entry.resolvedURL
      do {
        let data = try FileMetadataReader().readData(
          from: manifestURL,
          maximumByteCount: 10_000_000,
          expectedIdentity: entry.resolvedIdentity
        )
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.descriptors.count <= Self.maximumManifestDescriptorCount else {
          issues.append(issue(source: source, code: "OLLAMA_MANIFEST_TOO_LARGE", url: manifestURL))
          continue
        }
        parsedManifests.append(
          ParsedManifest(
            entry: entry,
            manifest: manifest,
            location: location(for: manifestURL, root: source.rootURL))
        )
      } catch {
        issues.append(issue(source: source, code: "OLLAMA_MANIFEST_INVALID", url: manifestURL))
      }
    }

    let digestUseCounts =
      parsedManifests
      .flatMap { $0.manifest.descriptors.map(\.digest) }
      .reduce(into: [String: Int]()) { counts, digest in counts[digest, default: 0] += 1 }

    let installations = parsedManifests.compactMap { parsed -> ModelInstallation? in
      guard let location = parsed.location else {
        issues.append(issue(source: source, code: "OLLAMA_MANIFEST_PATH_INVALID", url: parsed.url))
        return nil
      }

      var artifacts: [Artifact] = []
      if let manifestArtifact = artifact(
        for: parsed.entry.resolvedURL,
        expectedIdentity: parsed.entry.resolvedIdentity,
        kind: .manifest
      ) {
        artifacts.append(manifestArtifact)
      }

      var isIncomplete = false
      for descriptor in parsed.manifest.descriptors {
        guard let blobURL = blobURL(for: descriptor.digest, source: source) else {
          isIncomplete = true
          issues.append(
            issue(source: source, code: "OLLAMA_BLOB_REFERENCE_INVALID", url: parsed.url)
          )
          continue
        }
        guard let blobEntry = entries.first(where: { $0.resolvedURL == blobURL }),
          let blobArtifact = artifact(
            for: blobEntry.resolvedURL,
            expectedIdentity: blobEntry.resolvedIdentity,
            kind: .weights,
            isShared: (digestUseCounts[descriptor.digest] ?? 0) > 1
          )
        else {
          isIncomplete = true
          issues.append(issue(source: source, code: "OLLAMA_BLOB_MISSING", url: blobURL))
          continue
        }
        artifacts.append(blobArtifact)
      }

      let identityID = "ollama:\(location.modelName.lowercased())"
      let variantID = "\(identityID):\(location.tag.lowercased())"
      let identity = ModelIdentity(id: identityID, displayName: location.modelName)
      let variant = ModelVariant(id: variantID, identityID: identityID, format: .ollama)
      return ModelInstallation(
        id: "\(source.id):\(parsed.url.path)",
        identity: identity,
        variant: variant,
        sourceID: source.id,
        providerID: id,
        rootURL: parsed.url,
        state: isIncomplete ? .incomplete : .stored,
        artifacts: artifacts,
        configurationURLs: [],
        timestamps: timestamps(
          for: parsed.entry.resolvedURL,
          expectedIdentity: parsed.entry.resolvedIdentity
        ),
        modelCard: modelCard(for: location)
      )
    }

    let partialInstallations = partialBlobEntries.compactMap { entry -> ModelInstallation? in
      let partialURL = entry.resolvedURL
      guard
        let artifact = artifact(
          for: partialURL,
          expectedIdentity: entry.resolvedIdentity,
          kind: .weights,
          isPartial: true
        )
      else {
        issues.append(
          issue(source: source, code: "OLLAMA_PARTIAL_BLOB_UNREADABLE", url: partialURL))
        return nil
      }

      let digest = String(partialURL.lastPathComponent.dropLast("-partial".count))
      let identityID = "ollama:incomplete:\(digest)"
      let identity = ModelIdentity(
        id: identityID,
        displayName: "Ollama download in progress"
      )
      let variant = ModelVariant(
        id: "\(identityID):partial",
        identityID: identityID,
        format: .ollama
      )
      return ModelInstallation(
        id: "\(source.id):\(partialURL.path)",
        identity: identity,
        variant: variant,
        sourceID: source.id,
        providerID: id,
        rootURL: partialURL,
        state: .incomplete,
        artifacts: [artifact],
        configurationURLs: [],
        timestamps: timestamps(for: partialURL, expectedIdentity: entry.resolvedIdentity)
      )
    }

    return AdapterScanResult(
      source: source,
      installations: installations + partialInstallations,
      issues: issues
    )
  }

  private func isPartialBlob(_ url: URL, root: URL) -> Bool {
    let blobsURL = root.appending(path: "blobs", directoryHint: .isDirectory)
    guard
      url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
        == blobsURL.resolvingSymlinksInPath().standardizedFileURL.path
    else { return false }
    let name = url.lastPathComponent
    guard name.hasPrefix("sha256-"), name.hasSuffix("-partial") else { return false }
    let digest = name.dropFirst("sha256-".count).dropLast("-partial".count)
    return digest.count == 64
      && digest.allSatisfy { $0.isHexDigit }
  }

  private func blobURL(for digest: String, source: ScanSource) -> URL? {
    let sha256Pattern = #"^sha256:[0-9a-fA-F]{64}$"#
    guard digest.range(of: sha256Pattern, options: .regularExpression) != nil else { return nil }
    let candidate =
      source.rootURL
      .appending(path: "blobs", directoryHint: .isDirectory)
      .appending(path: digest.replacingOccurrences(of: ":", with: "-"))
    guard let rootIdentity = source.rootIdentity else { return nil }
    return try? ScopedPathPolicy(
      rootURL: source.rootURL,
      volumeIdentity: source.volumeIdentity,
      expectedRootIdentity: rootIdentity
    ).validate(candidate)
  }

  private func location(for manifestURL: URL, root: URL) -> ManifestLocation? {
    let relativePath = manifestURL.path.dropFirst(root.path.count)
    let components = relativePath.split(separator: "/").map(String.init)
    guard let manifestsIndex = components.firstIndex(of: "manifests") else { return nil }
    let locationComponents = Array(components.dropFirst(manifestsIndex + 1))
    guard locationComponents.count >= 4,
      let host = locationComponents.first,
      let tag = locationComponents.last
    else { return nil }

    var modelComponents = Array(locationComponents.dropFirst().dropLast())
    if modelComponents.first == "library" {
      modelComponents.removeFirst()
    }
    guard !modelComponents.isEmpty else { return nil }
    return ManifestLocation(host: host, modelName: modelComponents.joined(separator: "/"), tag: tag)
  }

  private func modelCard(for location: ManifestLocation) -> ModelCardLink? {
    guard location.host == "registry.ollama.ai" else { return nil }
    var components = URLComponents()
    components.scheme = "https"
    components.host = "ollama.com"
    components.path = "/library/\(location.modelName)"
    guard let url = components.url else { return nil }
    return ModelCardLink(url: url, confidence: .confirmed, evidence: "Ollama manifest path")
  }

  private func artifact(
    for url: URL,
    expectedIdentity: DeletionFileIdentity? = nil,
    kind: ArtifactKind,
    isShared: Bool = false,
    isPartial: Bool = false
  ) -> Artifact? {
    guard
      let metadata = try? FileMetadataReader().metadata(
        for: url,
        expectedIdentity: expectedIdentity
      )
    else { return nil }
    return Artifact(
      id: "ollama:\(url.path)",
      url: url,
      kind: kind,
      logicalByteCount: metadata.logicalByteCount,
      allocatedByteCount: metadata.allocatedByteCount,
      physicalIdentifier: metadata.physicalIdentifier,
      isShared: isShared,
      isPartial: isPartial
    )
  }

  private func timestamps(
    for url: URL,
    expectedIdentity: DeletionFileIdentity? = nil
  ) -> [ObservedTimestamp] {
    guard
      let metadata = try? FileMetadataReader().metadata(
        for: url,
        expectedIdentity: expectedIdentity
      )
    else { return [] }
    var timestamps: [ObservedTimestamp] = []
    if let creationDate = metadata.creationDate {
      timestamps.append(
        ObservedTimestamp(value: creationDate, kind: .fileCreation, confidence: .derived)
      )
    }
    if let modificationDate = metadata.modificationDate {
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

  private func issue(source: ScanSource, code: String, url: URL) -> InventoryIssue {
    InventoryIssue(
      id: "\(source.id):\(code):\(url.path)",
      code: code,
      severity: .warning,
      sourceID: source.id,
      summary: "Ollama inventory data is incomplete or invalid.",
      affectedURL: url
    )
  }
}

private struct Manifest: Decodable {
  let config: Descriptor?
  let layers: [Descriptor]

  var descriptors: [Descriptor] {
    if let config { return [config] + layers }
    return layers
  }
}

private struct Descriptor: Decodable {
  let digest: String
  let size: Int64?
  let mediaType: String?
}

private struct ParsedManifest {
  let entry: FileSystemEntry
  let manifest: Manifest
  let location: ManifestLocation?

  var url: URL { entry.url }
}

private struct ManifestLocation {
  let host: String
  let modelName: String
  let tag: String
}
