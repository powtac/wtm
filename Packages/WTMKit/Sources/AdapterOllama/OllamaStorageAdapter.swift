import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct OllamaStorageAdapter: StorageProviderAdapter {
  public let id = ProviderID.ollama
  public let displayName = "Ollama"

  public init() {}

  public func scan(source: ScanSource) async -> AdapterScanResult {
    let entries: [FileSystemEntry]
    do {
      entries = try ReadOnlyDirectoryWalker().entries(under: source.rootURL)
    } catch {
      return AdapterScanResult(
        source: source,
        installations: [],
        issues: [issue(source: source, code: "OLLAMA_ENUMERATION_FAILED", url: source.rootURL)]
      )
    }

    let manifestURLs = entries.filter {
      ($0.isRegularFile || $0.isSymbolicLink) && $0.url.path.contains("/manifests/")
    }.map(\.url)
    var parsedManifests: [ParsedManifest] = []
    var issues: [InventoryIssue] = []

    for manifestURL in manifestURLs {
      do {
        let data = try FileMetadataReader().readData(
          from: manifestURL, maximumByteCount: 10_000_000)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        parsedManifests.append(
          ParsedManifest(
            url: manifestURL, manifest: manifest,
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
      if let manifestArtifact = artifact(for: parsed.url, kind: .manifest) {
        artifacts.append(manifestArtifact)
      }

      var isIncomplete = false
      for descriptor in parsed.manifest.descriptors {
        guard let blobURL = blobURL(for: descriptor.digest, root: source.rootURL) else {
          isIncomplete = true
          issues.append(
            issue(source: source, code: "OLLAMA_BLOB_REFERENCE_INVALID", url: parsed.url)
          )
          continue
        }
        guard
          let blobArtifact = artifact(
            for: blobURL,
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
        timestamps: timestamps(for: parsed.url),
        modelCard: modelCard(for: location)
      )
    }

    return AdapterScanResult(source: source, installations: installations, issues: issues)
  }

  private func blobURL(for digest: String, root: URL) -> URL? {
    let sha256Pattern = #"^sha256:[0-9a-fA-F]{64}$"#
    guard digest.range(of: sha256Pattern, options: .regularExpression) != nil else { return nil }
    let candidate =
      root
      .appending(path: "blobs", directoryHint: .isDirectory)
      .appending(path: digest.replacingOccurrences(of: ":", with: "-"))
    return try? ScopedPathPolicy(rootURL: root).validate(candidate)
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
    kind: ArtifactKind,
    isShared: Bool = false
  ) -> Artifact? {
    guard let metadata = try? FileMetadataReader().metadata(for: url) else { return nil }
    return Artifact(
      id: "ollama:\(url.path)",
      url: url,
      kind: kind,
      logicalByteCount: metadata.logicalByteCount,
      allocatedByteCount: metadata.allocatedByteCount,
      physicalIdentifier: metadata.physicalIdentifier,
      isShared: isShared
    )
  }

  private func timestamps(for url: URL) -> [ObservedTimestamp] {
    guard let metadata = try? FileMetadataReader().metadata(for: url) else { return [] }
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
  let url: URL
  let manifest: Manifest
  let location: ManifestLocation?
}

private struct ManifestLocation {
  let host: String
  let modelName: String
  let tag: String
}
