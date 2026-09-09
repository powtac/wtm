import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

/// Supports Jan's documented flat model.yml contract under an approved data directory.
public struct JanStorageAdapter: StorageProviderAdapter {
  public let id = ProviderID.jan
  public let displayName = "Jan"
  public init() {}

  public func scan(source: ScanSource) async -> AdapterScanResult {
    var models: [ModelInstallation] = []
    var issues: [InventoryIssue] = []
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(300))
    do {
      let root = source.rootURL.appending(path: "llamacpp/models")
      var entries: [String: FileSystemEntry] = [:]
      for try await entry in ReadOnlyDirectoryWalker().entryStream(
        under: root, approvedBy: source, budget: DirectoryWalkerBudget(maximumEntryCount: 50_000)
      ) {
        guard !Task.isCancelled else { break }
        if entry.isRegularFile || entry.isSymbolicLink {
          entries[entry.url.standardizedFileURL.path] = entry
        }
      }
      for manifest in entries.values.filter({ $0.url.lastPathComponent == "model.yml" }).sorted(
        by: { $0.url.path < $1.url.path })
      {
        guard !Task.isCancelled else { break }
        guard clock.now < deadline else {
          issues.append(issue(source, source.rootURL, "JAN_SCAN_INCOMPLETE"))
          break
        }
        do {
          let fields = try parse(manifest)
          guard let path = fields["model_path"], let name = fields["name"], !name.isEmpty,
            let size = fields["size_bytes"].flatMap(Int64.init), size > 0,
            ["true", "false"].contains(fields["embedding"] ?? ""),
            path.hasPrefix("llamacpp/models/"), !path.split(separator: "/").contains(".."),
            !path.contains("\\"), path.hasSuffix(".gguf")
          else { throw JanError.unsupported }
          if let hash = fields["model_sha256"],
            hash.range(of: #"^[a-fA-F0-9]{64}$"#, options: .regularExpression) == nil
          {
            throw JanError.unsupported
          }
          let file = source.rootURL.appending(path: path).standardizedFileURL
          guard
            file.deletingLastPathComponent()
              == manifest.url.deletingLastPathComponent().standardizedFileURL
          else { throw JanError.unsupported }
          let entry = entries[file.path]
          let metadata = try entry.map {
            try FileMetadataReader().metadata(
              for: $0.resolvedURL, expectedIdentity: $0.resolvedIdentity)
          }
          let inspection = try entry.map {
            try GGUFHeaderReader().inspect(
              at: $0.resolvedURL, expectedIdentity: $0.resolvedIdentity)
          }
          let split =
            file.lastPathComponent.range(
              of: #"-\d{5}-of-\d{5}\.gguf$"#, options: .regularExpression) != nil
          let complete =
            metadata?.logicalByteCount == size && inspection?.containsModelWeights == true && !split
          let identity = "jan:\(path)"
          let artifacts =
            metadata.map { value in
              [
                Artifact(
                  id: identity, url: file, kind: .weights, logicalByteCount: value.logicalByteCount,
                  allocatedByteCount: value.allocatedByteCount,
                  physicalIdentifier: value.physicalIdentifier,
                  isPartial: !complete)
              ]
            } ?? []
          models.append(
            ModelInstallation(
              id: "\(source.id):\(manifest.url.path)",
              identity: ModelIdentity(id: identity, displayName: name),
              variant: ModelVariant(
                id: identity, identityID: identity, format: complete ? .gguf : .unknown),
              sourceID: source.id, providerID: id, rootURL: file,
              state: complete ? .stored : .incomplete,
              artifacts: artifacts
            ))
          if !complete { issues.append(issue(source, manifest.url, "JAN_MODEL_INCOMPLETE")) }
        } catch { issues.append(issue(source, manifest.url, "JAN_MANIFEST_UNSUPPORTED")) }
      }
    } catch { issues.append(issue(source, source.rootURL, "JAN_SCAN_INCOMPLETE")) }
    return AdapterScanResult(source: source, installations: models, issues: issues)
  }

  // Deliberately not a YAML interpreter: only the documented flat scalar schema is accepted.
  private func parse(_ entry: FileSystemEntry) throws -> [String: String] {
    guard !ConfigurationFilePolicy().isSecretSuspect(entry.resolvedURL) else {
      throw JanError.unsupported
    }
    let data = try FileMetadataReader().readData(
      from: entry.resolvedURL, maximumByteCount: 65_537, expectedIdentity: entry.resolvedIdentity)
    guard data.count <= 65_536, let text = String(data: data, encoding: .utf8) else {
      throw JanError.unsupported
    }
    let keys = Set(["model_path", "name", "size_bytes", "embedding", "model_sha256"])
    var result: [String: String] = [:]
    for line in text.split(whereSeparator: \.isNewline) {
      if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
      guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let separator = line.firstIndex(of: ":")
      else { throw JanError.unsupported }
      let key = String(line[..<separator])
      var value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
      guard keys.contains(key), result[key] == nil, !value.isEmpty else {
        throw JanError.unsupported
      }
      if value.hasPrefix("\"") {
        value = try JSONDecoder().decode(String.self, from: Data(value.utf8))
      } else {
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: "'&*!{}[]|>#%`")) == nil,
          !value.contains(": ")
        else { throw JanError.unsupported }
      }
      guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
      else { throw JanError.unsupported }
      result[key] = value
    }
    return result
  }

  private func issue(_ source: ScanSource, _ url: URL, _ code: String) -> InventoryIssue {
    InventoryIssue(
      id: "\(source.id):\(url.path):\(code)", code: code, severity: .warning,
      sourceID: source.id,
      summary: "Jan model metadata or local weights could not be fully verified.", affectedURL: url)
  }
}

private enum JanError: Error { case unsupported }
