import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

/// Read-only recognition of model directories produced by MLX-LM conversion.
///
/// Safetensors plus a Transformers config is intentionally insufficient evidence. WTM
/// requires the MLX-LM quantization schema before assigning the MLX format.
public struct MLXStorageAdapter: StorageProviderAdapter {
  private static let maximumConfigurationByteCount = 2 * 1_024 * 1_024
  private static let recognizedQuantizationModes = Set([
    "affine", "mxfp4", "mxfp8", "nvfp4",
  ])
  private static let tokenizerNames = Set([
    "merges.txt",
    "sentencepiece.bpe.model",
    "special_tokens_map.json",
    "tokenizer.json",
    "tokenizer.model",
    "tokenizer_config.json",
    "vocab.json",
  ])

  public let id = ProviderID.mlx
  public let displayName = "MLX"

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
        do {
          var filesByDirectory: [URL: [FileSystemEntry]] = [:]
          for try await entry in ReadOnlyDirectoryWalker().entryStream(
            under: source.rootURL,
            approvedBy: source
          ) {
            guard !Task.isCancelled else {
              continuation.finish()
              return
            }
            guard entry.isRegularFile || entry.isSymbolicLink else { continue }
            guard Self.isRelevant(entry.url) else { continue }
            filesByDirectory[entry.url.deletingLastPathComponent(), default: []].append(entry)
          }

          for directory in filesByDirectory.keys.sorted(by: { $0.path < $1.path }) {
            guard !Task.isCancelled else {
              continuation.finish()
              return
            }
            guard let entries = filesByDirectory[directory] else { continue }
            let result = inspect(directory: directory, entries: entries, source: source)
            if result.installation != nil || !result.issues.isEmpty {
              continuation.yield(
                AdapterScanBatch(
                  installations: result.installation.map { [$0] } ?? [],
                  issues: result.issues
                )
              )
            }
          }
        } catch {
          continuation.yield(
            AdapterScanBatch(
              installations: [],
              issues: [
                issue(
                  source: source,
                  code: "MLX_ENUMERATION_FAILED",
                  severity: .error,
                  summary: "The selected MLX source could not be inventoried.",
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

  private func inspect(
    directory: URL,
    entries: [FileSystemEntry],
    source: ScanSource
  ) -> (installation: ModelInstallation?, issues: [InventoryIssue]) {
    guard let configEntry = entries.first(where: { $0.url.lastPathComponent == "config.json" })
    else { return (nil, []) }

    let parsedConfiguration: ParsedConfiguration
    do {
      parsedConfiguration = try parseConfiguration(at: configEntry.resolvedURL)
    } catch {
      return (
        nil,
        [
          issue(
            source: source,
            code: "MLX_CONFIGURATION_INVALID",
            severity: .warning,
            summary: "A candidate config could not be validated as MLX-LM metadata.",
            url: configEntry.url
          )
        ]
      )
    }

    guard parsedConfiguration.isMLXQuantization else {
      return (
        nil,
        [
          issue(
            source: source,
            code: "MLX_STRUCTURE_UNCONFIRMED",
            severity: .info,
            summary: "Safetensors and config files do not prove an MLX model.",
            url: directory
          )
        ]
      )
    }

    let weightEntries = entries.filter { Self.isWeight($0.url) }
    let partialEntries = entries.filter { Self.isPartial($0.url) }
    let tokenizerEntries = entries.filter { Self.isTokenizer($0.url) }
    let expectedWeights = expectedWeightNames(from: entries)
    let presentWeightNames = Set(weightEntries.map(\.url.lastPathComponent))
    let missingIndexedWeights = expectedWeights.subtracting(presentWeightNames)
    let weightsComplete =
      !weightEntries.isEmpty && partialEntries.isEmpty
      && missingIndexedWeights.isEmpty
    let tokenizerComplete = !tokenizerEntries.isEmpty
    let state: InstallationState = weightsComplete && tokenizerComplete ? .stored : .incomplete

    var issues: [InventoryIssue] = []
    if !weightsComplete {
      issues.append(
        issue(
          source: source,
          code: "MLX_WEIGHTS_INCOMPLETE",
          severity: .warning,
          summary: "The MLX weight set is missing, partial, or has unresolved shards.",
          url: directory
        )
      )
    }
    if !tokenizerComplete {
      issues.append(
        issue(
          source: source,
          code: "MLX_TOKENIZER_MISSING",
          severity: .warning,
          summary: "The MLX model has no recognized local tokenizer artifact.",
          url: directory
        )
      )
    }

    let sortedEntries = entries.sorted { $0.url.path < $1.url.path }
    let physicalCounts = Dictionary(
      grouping: sortedEntries.compactMap { entry -> (String, FileMetadata)? in
        guard let metadata = try? FileMetadataReader().metadata(for: entry.resolvedURL),
          let identifier = metadata.physicalIdentifier
        else { return nil }
        return (identifier, metadata)
      },
      by: \.0
    ).mapValues(\.count)
    let artifacts = sortedEntries.compactMap { entry -> Artifact? in
      guard let metadata = try? FileMetadataReader().metadata(for: entry.resolvedURL) else {
        return nil
      }
      return Artifact(
        id: "mlx:\(entry.url.path)",
        url: entry.url,
        kind: artifactKind(for: entry.url),
        logicalByteCount: metadata.logicalByteCount,
        allocatedByteCount: metadata.allocatedByteCount,
        physicalIdentifier: metadata.physicalIdentifier,
        isShared: metadata.physicalIdentifier.map { (physicalCounts[$0] ?? 0) > 1 } ?? false,
        isPartial: Self.isPartial(entry.url)
      )
    }

    let repository = repositoryIdentity(for: directory, under: source.rootURL)
    let displayName =
      repository?.split(separator: "/").last.map(String.init)
      ?? directory.lastPathComponent
    let identityID = "mlx:\((repository ?? directory.path).lowercased())"
    let quantization = parsedConfiguration.quantizationDescription
    let identity = ModelIdentity(
      id: identityID,
      displayName: displayName,
      family: parsedConfiguration.modelType
    )
    let variant = ModelVariant(
      id: "\(identityID):\(quantization ?? "unknown")",
      identityID: identityID,
      format: .mlx,
      quantization: quantization
    )
    let configurationURLs = sortedEntries.map(\.url).filter(
      ConfigurationFilePolicy().isAllowed
    )
    return (
      ModelInstallation(
        id: "\(source.id):mlx:\(directory.path)",
        identity: identity,
        variant: variant,
        sourceID: source.id,
        providerID: id,
        rootURL: directory,
        state: state,
        artifacts: artifacts,
        configurationURLs: configurationURLs,
        timestamps: timestamps(in: sortedEntries),
        modelCard: repository.flatMap(modelCard)
      ),
      issues
    )
  }

  private func parseConfiguration(at url: URL) throws -> ParsedConfiguration {
    let data = try FileMetadataReader().readData(
      from: url,
      maximumByteCount: Self.maximumConfigurationByteCount + 1
    )
    guard data.count <= Self.maximumConfigurationByteCount,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw MLXConfigurationError.invalid }

    let quantization = object["quantization"] as? [String: Any]
    let fallback = object["quantization_config"] as? [String: Any]
    let candidate = quantization ?? fallback
    let bits = Self.integer(candidate?["bits"])
    let groupSize = Self.integer(candidate?["group_size"])
    let mode = (candidate?["mode"] as? String)?.lowercased() ?? "affine"
    let hasForeignMethod = candidate?["quant_method"] != nil
    let isMLXQuantization =
      !hasForeignMethod
      && bits.map { (1...16).contains($0) } == true
      && groupSize.map { (8...1_024).contains($0) } == true
      && Self.recognizedQuantizationModes.contains(mode)

    let modelType =
      object["model_type"] as? String
      ?? (object["text_config"] as? [String: Any])?["model_type"] as? String
    return ParsedConfiguration(
      modelType: modelType,
      bits: bits,
      groupSize: groupSize,
      mode: mode,
      isMLXQuantization: isMLXQuantization
    )
  }

  private func expectedWeightNames(from entries: [FileSystemEntry]) -> Set<String> {
    guard
      let index = entries.first(where: {
        $0.url.lastPathComponent == "model.safetensors.index.json"
      }),
      let data = try? FileMetadataReader().readData(
        from: index.resolvedURL,
        maximumByteCount: Self.maximumConfigurationByteCount + 1
      ),
      data.count <= Self.maximumConfigurationByteCount,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let weightMap = object["weight_map"] as? [String: String]
    else { return [] }
    return Set(weightMap.values.filter(Self.isSafeFileName))
  }

  private func repositoryIdentity(for directory: URL, under root: URL) -> String? {
    let rootPath = root.standardizedFileURL.path
    let directoryPath = directory.standardizedFileURL.path
    guard directoryPath == rootPath || directoryPath.hasPrefix(rootPath + "/") else {
      return nil
    }
    for component in directory.pathComponents.reversed() where component.hasPrefix("models--") {
      let encoded = String(component.dropFirst("models--".count))
      let repository = encoded.replacingOccurrences(of: "--", with: "/")
      let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
      guard parts.count == 2, parts.allSatisfy({ Self.isRepositoryComponent(String($0)) })
      else { return nil }
      return repository
    }
    return nil
  }

  private func modelCard(for repository: String) -> ModelCardLink? {
    guard let url = URL(string: "https://huggingface.co/\(repository)") else { return nil }
    return ModelCardLink(
      url: url,
      confidence: .confirmed,
      evidence: "Hugging Face cache key for structurally confirmed MLX-LM model"
    )
  }

  private func timestamps(in entries: [FileSystemEntry]) -> [ObservedTimestamp] {
    let metadata = entries.compactMap {
      try? FileMetadataReader().metadata(for: $0.resolvedURL)
    }
    var result: [ObservedTimestamp] = []
    if let creationDate = metadata.compactMap(\.creationDate).min() {
      result.append(
        ObservedTimestamp(value: creationDate, kind: .fileCreation, confidence: .derived)
      )
    }
    if let modificationDate = metadata.compactMap(\.modificationDate).min() {
      result.append(
        ObservedTimestamp(
          value: modificationDate,
          kind: .fileModification,
          confidence: .heuristic
        )
      )
    }
    return result
  }

  private func issue(
    source: ScanSource,
    code: String,
    severity: IssueSeverity,
    summary: String,
    url: URL
  ) -> InventoryIssue {
    InventoryIssue(
      id: "\(source.id):\(code):\(url.path)",
      code: code,
      severity: severity,
      sourceID: source.id,
      summary: summary,
      affectedURL: url
    )
  }

  private func artifactKind(for url: URL) -> ArtifactKind {
    if Self.isWeight(url) || Self.isPartial(url) { return .weights }
    if url.lastPathComponent == "config.json" { return .configuration }
    if Self.isTokenizer(url) { return .tokenizer }
    if url.lastPathComponent == "model.safetensors.index.json" { return .manifest }
    return .metadata
  }

  private static func isRelevant(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    return name == "config.json" || name == "model.safetensors.index.json"
      || isWeight(url) || isPartial(url) || isTokenizer(url)
      || name == "generation_config.json" || name == "readme.md"
  }

  private static func isWeight(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    return name.hasPrefix("model") && name.hasSuffix(".safetensors")
  }

  private static func isPartial(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    return name.hasPrefix("model")
      && (name.hasSuffix(".safetensors.incomplete") || name.hasSuffix(".safetensors.part"))
  }

  private static func isTokenizer(_ url: URL) -> Bool {
    tokenizerNames.contains(url.lastPathComponent.lowercased())
  }

  private static func integer(_ value: Any?) -> Int? {
    switch value {
    case let value as Int: value
    case let value as NSNumber: value.intValue
    default: nil
    }
  }

  private static func isSafeFileName(_ name: String) -> Bool {
    !name.isEmpty && name == URL(filePath: name).lastPathComponent
      && !name.contains("..") && !name.contains("/") && !name.contains("\\")
  }

  private static func isRepositoryComponent(_ value: String) -> Bool {
    guard !value.isEmpty, value.count <= 96 else { return false }
    return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression)
      != nil
  }
}

private enum MLXConfigurationError: Error {
  case invalid
}

private struct ParsedConfiguration {
  let modelType: String?
  let bits: Int?
  let groupSize: Int?
  let mode: String
  let isMLXQuantization: Bool

  var quantizationDescription: String? {
    guard let bits, let groupSize else { return nil }
    return "\(bits)-bit \(mode), group \(groupSize)"
  }
}
