import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

/// Read-only GGUF inventory for an explicitly approved LM Studio models directory.
/// Directory names describe an import location, never repository or runtime ownership.
public struct LMStudioStorageAdapter: StorageProviderAdapter {
  public let id = ProviderID.lmStudio
  public let displayName = "LM Studio"
  private let budget: DirectoryWalkerBudget

  public init(budget: DirectoryWalkerBudget = DirectoryWalkerBudget()) {
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
        do {
          for try await entry in ReadOnlyDirectoryWalker().entryStream(
            under: source.rootURL, approvedBy: source, budget: budget
          ) {
            guard !Task.isCancelled else { break }
            guard entry.isRegularFile || entry.isSymbolicLink else { continue }
            guard
              ["gguf", "incomplete", "safetensors"].contains(entry.url.pathExtension.lowercased())
            else { continue }
            do {
              continuation.yield(try inspect(entry, source: source))
            } catch {
              continuation.yield(issue(source, url: entry.url, code: "LM_STUDIO_FILE_UNVERIFIED"))
            }
          }
        } catch is CancellationError {
          // Cancelling an inventory is not an unreadable-file finding.
        } catch {
          continuation.yield(issue(source, url: source.rootURL, code: "LM_STUDIO_SCAN_INCOMPLETE"))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func inspect(_ entry: FileSystemEntry, source: ScanSource) throws -> AdapterScanBatch {
    let rootComponents = source.rootURL.standardizedFileURL.pathComponents
    let components = entry.url.standardizedFileURL.pathComponents
    let hasImportLayout =
      components.starts(with: rootComponents)
      && components.count == rootComponents.count + 3
    let partial = entry.url.pathExtension.lowercased() == "incomplete"
    let inspection =
      entry.url.pathExtension.lowercased() == "gguf"
      ? try GGUFHeaderReader().inspect(
        at: entry.resolvedURL, expectedIdentity: entry.resolvedIdentity)
      : nil
    let isSplit =
      entry.url.lastPathComponent.range(
        of: #"-\d{5}-of-\d{5}\.gguf$"#, options: [.regularExpression, .caseInsensitive]
      ) != nil
    let confirmed = hasImportLayout && inspection != nil && !isSplit
    let metadata = try FileMetadataReader().metadata(
      for: entry.resolvedURL, expectedIdentity: entry.resolvedIdentity)
    let relativePath = components.dropFirst(rootComponents.count).joined(separator: "/")
    let identityID = "lm-studio:\(relativePath)"
    let name = entry.url.deletingPathExtension().lastPathComponent
    let quantization = name.range(of: #"(?i)(Q[2-8](?:_[A-Z0-9]+)*)"#, options: .regularExpression)
      .map { String(name[$0]).uppercased() }
    let state: InstallationState =
      partial || (confirmed && inspection?.containsModelWeights == false)
      ? .incomplete : (confirmed ? .stored : .issue)
    let kind: ArtifactKind =
      confirmed
      ? (inspection?.containsModelWeights == true ? .weights : .tokenizer) : .unknown
    let modelCard =
      confirmed
      ? inspection?.huggingFaceRepositoryID.flatMap { repositoryID in
        URL(string: "https://huggingface.co/\(repositoryID)").map {
          ModelCardLink(
            url: $0, confidence: .confirmed,
            evidence: "Validated GGUF Hugging Face repository metadata")
        }
      } : nil
    let timestamps =
      metadata.creationDate.map {
        [ObservedTimestamp(value: $0, kind: .fileCreation, confidence: .derived)]
      } ?? []
    let installation = ModelInstallation(
      id: "\(source.id):\(entry.url.path)",
      identity: ModelIdentity(id: identityID, displayName: name),
      variant: ModelVariant(
        id: "\(identityID):\(confirmed ? "gguf" : "unknown")",
        identityID: identityID,
        format: confirmed ? .gguf : .unknown,
        quantization: confirmed && kind == .weights ? quantization : nil
      ),
      sourceID: source.id,
      providerID: id,
      rootURL: entry.url,
      state: state,
      artifacts: [
        Artifact(
          id: "lm-studio:\(entry.url.path)",
          url: entry.url,
          kind: kind,
          logicalByteCount: metadata.logicalByteCount,
          allocatedByteCount: metadata.allocatedByteCount,
          physicalIdentifier: metadata.physicalIdentifier,
          isPartial: partial
        )
      ],
      timestamps: timestamps,
      modelCard: modelCard
    )
    return AdapterScanBatch(
      installations: [installation],
      issues: confirmed ? [] : issue(source, url: entry.url, code: "LM_STUDIO_UNCONFIRMED").issues
    )
  }

  private func issue(_ source: ScanSource, url: URL, code: String) -> AdapterScanBatch {
    AdapterScanBatch(
      installations: [],
      issues: [
        InventoryIssue(
          id: "\(source.id):\(url.path):\(code)",
          code: code,
          severity: .warning,
          sourceID: source.id,
          summary:
            "This LM Studio source has an unverified file, layout, or completeness. Inventory may be incomplete.",
          affectedURL: url
        )
      ])
  }
}
