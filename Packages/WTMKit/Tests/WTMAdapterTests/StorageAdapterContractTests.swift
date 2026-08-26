import AdapterHuggingFace
import AdapterMLX
import AdapterManual
import AdapterOllama
import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain
import WTMInventory

@Test("Ollama manifests resolve their referenced blobs")
func ollamaFixtureIsInventoried() async throws {
  let root = try #require(fixtureRoot("ollama"))
  let source = allowedSource(id: "ollama", provider: .ollama, root: root)

  let result = await OllamaStorageAdapter().scan(source: source)

  #expect(result.installations.count == 1)
  #expect(result.installations.first?.identity.displayName == "tiny")
  #expect(result.installations.first?.state == .stored)
}

@Test("Ollama rejects a digest that could escape the blob directory")
func ollamaRejectsInvalidDigestPath() async throws {
  let fileManager = FileManager.default
  let root = fileManager.temporaryDirectory.appending(
    path: "wtm-ollama-\(UUID().uuidString)", directoryHint: .isDirectory)
  defer { try? fileManager.removeItem(at: root) }

  let manifest = root.appending(
    path: "manifests/registry.ollama.ai/library/tiny/latest", directoryHint: .notDirectory)
  try fileManager.createDirectory(
    at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data(
    #"{"schemaVersion":2,"config":{"digest":"sha256:../../outside","size":1},"layers":[]}"#
      .utf8
  ).write(to: manifest)

  let source = allowedSource(id: "ollama-invalid", provider: .ollama, root: root)
  let result = await OllamaStorageAdapter().scan(source: source)

  #expect(result.installations.first?.state == .incomplete)
  #expect(result.issues.contains { $0.code == "OLLAMA_BLOB_REFERENCE_INVALID" })
}

@Test("Hugging Face cache keys create confirmed model-card links")
func huggingFaceFixtureIsInventoried() async throws {
  let root = try #require(fixtureRoot("huggingface"))
  let source = allowedSource(id: "hf", provider: .huggingFace, root: root)
  let adapter = try HuggingFaceStorageAdapter()

  let result = await adapter.scan(source: source)

  #expect(result.installations.count == 2)
  let tiny = try #require(result.installations.first { $0.identity.family == "acme/tiny" })
  #expect(tiny.identity.family == "acme/tiny")
  #expect(
    tiny.modelCard?.url.absoluteString == "https://huggingface.co/acme/tiny")
  #expect(tiny.modelCard?.evidence == "Hugging Face cache key")
  #expect(result.installations.contains { $0.state == .incomplete })
  #expect(result.issues.contains { $0.code == "HF_DOWNLOAD_INCOMPLETE" })
}

@Test("Hugging Face aliases restore owners without guessing unknown shorthand caches")
func huggingFaceAliasesRestoreRepositoryOwners() async throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  defer { try? FileManager.default.removeItem(at: root) }
  for repositoryName in ["gpt-oss-20b", "unknown-model"] {
    let snapshot = root.appending(
      path: "models--\(repositoryName)/snapshots/local",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: snapshot.appending(path: "config.json"))
  }

  let adapter = try HuggingFaceStorageAdapter()
  let result = await adapter.scan(
    source: allowedSource(id: "hf-alias", provider: .huggingFace, root: root)
  )

  let gptOSS = try #require(
    result.installations.first { $0.identity.displayName == "gpt-oss-20b" }
  )
  #expect(gptOSS.identity.family == "openai/gpt-oss-20b")
  #expect(gptOSS.modelCard?.url.absoluteString == "https://huggingface.co/openai/gpt-oss-20b")
  #expect(gptOSS.modelCard?.confidence == .confirmed)
  #expect(gptOSS.modelCard?.evidence == "WTM Hugging Face repository alias")

  let unknown = try #require(
    result.installations.first { $0.identity.displayName == "unknown-model" }
  )
  #expect(unknown.identity.family == nil)
  #expect(unknown.modelCard == nil)
}

@Test("Hugging Face repository aliases reject collisions and invalid values")
func huggingFaceRepositoryAliasesFailClosed() {
  #expect(
    throws: HuggingFaceRepositoryAliasError.normalizedKeyCollision("model")
  ) {
    _ = try HuggingFaceStorageAdapter(repositoryAliases: [
      "MODEL": "acme/first",
      "model": "acme/second",
    ])
  }
  #expect(
    throws: HuggingFaceRepositoryAliasError.invalidAliasKey("../model")
  ) {
    _ = try HuggingFaceStorageAdapter(repositoryAliases: ["../model": "acme/model"])
  }
  #expect(
    throws: HuggingFaceRepositoryAliasError.invalidRepositoryID("missing-owner")
  ) {
    _ = try HuggingFaceStorageAdapter(repositoryAliases: ["model": "missing-owner"])
  }
}

@Test("Manual folders detect GGUF quantization")
func manualFixtureIsInventoried() async throws {
  let root = try #require(fixtureRoot("manual"))
  let source = allowedSource(id: "manual", provider: .manual, root: root)

  let result = await ManualFolderAdapter().scan(source: source)

  #expect(result.installations.count == 1)
  #expect(result.installations.first?.variant.format == .gguf)
  #expect(result.installations.first?.variant.quantization == "Q4_K_M")
}

@Test("Manual scan stops visibly at its retained-entry budget")
func manualScanBudgetIsVisible() async throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: "wtm-manual-budget-\(UUID().uuidString)", directoryHint: .isDirectory
  )
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  for index in 0..<4 {
    try Data("gguf".utf8).write(to: root.appending(path: "model-\(index).gguf"))
  }
  let source = allowedSource(id: "manual-budget", provider: .manual, root: root)
  let adapter = ManualFolderAdapter(
    budget: ManualScanBudget(maximumEntryCount: 2, maximumDuration: .seconds(10))
  )

  let result = await adapter.scan(source: source)

  #expect(result.installations.count <= 2)
  #expect(result.issues.contains { $0.code == "MANUAL_SCAN_TRUNCATED" })
}

@Test("MLX-LM structures require config, weights, tokenizer, and explicit MLX quantization")
func mlxFixtureIsInventoried() async throws {
  let root = try #require(fixtureRoot("mlx"))
  let source = allowedSource(id: "mlx", provider: .mlx, root: root)

  let result = await MLXStorageAdapter().scan(source: source)

  let installation = try #require(result.installations.first)
  #expect(result.installations.count == 1)
  #expect(installation.providerID == .mlx)
  #expect(installation.variant.format == .mlx)
  #expect(installation.variant.quantization == "4-bit affine, group 64")
  #expect(installation.state == .stored)
  #expect(installation.artifacts.contains { $0.kind == .weights })
  #expect(installation.artifacts.contains { $0.kind == .configuration })
  #expect(installation.artifacts.contains { $0.kind == .tokenizer })
  #expect(installation.artifacts.allSatisfy { $0.physicalIdentifier != nil })
  #expect(result.issues.isEmpty)
}

@Test("Safetensors plus a generic Transformers config is not claimed as MLX")
func mlxRejectsFalsePositive() async throws {
  let fixture = try TemporaryMLXFixture()
  defer { fixture.remove() }
  try fixture.write("config.json", #"{"model_type":"llama"}"#)
  try fixture.write("model.safetensors", "not model weights")
  try fixture.write("tokenizer.json", "{}")

  let result = await MLXStorageAdapter().scan(source: fixture.source)

  #expect(result.installations.isEmpty)
  #expect(result.issues.contains { $0.code == "MLX_STRUCTURE_UNCONFIRMED" })
}

@Test("MLX partial weights and missing indexed shards remain incomplete")
func mlxReportsIncompleteArtifacts() async throws {
  let fixture = try TemporaryMLXFixture()
  defer { fixture.remove() }
  try fixture.write(
    "config.json",
    #"{"model_type":"llama","quantization":{"group_size":64,"bits":4,"mode":"affine"}}"#
  )
  try fixture.write("model-00001-of-00002.safetensors", "first shard")
  try fixture.write(
    "model.safetensors.index.json",
    #"{"weight_map":{"a":"model-00001-of-00002.safetensors","b":"model-00002-of-00002.safetensors"}}"#
  )
  try fixture.write("tokenizer.json", "{}")

  let result = await MLXStorageAdapter().scan(source: fixture.source)

  #expect(result.installations.first?.state == .incomplete)
  #expect(result.issues.contains { $0.code == "MLX_WEIGHTS_INCOMPLETE" })
}

@Test("MLX scanning never follows a weight symlink outside the approved source")
func mlxRejectsOutOfScopeSymlink() async throws {
  let fixture = try TemporaryMLXFixture()
  defer { fixture.remove() }
  let outsideURL = fixture.root.deletingLastPathComponent().appending(
    path: "outside-\(UUID().uuidString).safetensors"
  )
  defer { try? FileManager.default.removeItem(at: outsideURL) }
  try Data("outside".utf8).write(to: outsideURL)
  try fixture.write(
    "config.json",
    #"{"model_type":"llama","quantization":{"group_size":64,"bits":4}}"#
  )
  try fixture.write("tokenizer.json", "{}")
  try FileManager.default.createSymbolicLink(
    at: fixture.root.appending(path: "model.safetensors"),
    withDestinationURL: outsideURL
  )

  let result = await MLXStorageAdapter().scan(source: fixture.source)

  #expect(result.installations.first?.state == .incomplete)
  #expect(
    result.installations.first?.artifacts.contains {
      $0.url.lastPathComponent == "model.safetensors"
    } == false
  )
}

@Test("Opt-in real MLX source exposes only structurally confirmed MLX installations")
func realMLXSourceIsInventoried() async throws {
  guard let path = ProcessInfo.processInfo.environment["WTM_REAL_MLX_SOURCE"] else { return }
  let root = URL(filePath: path, directoryHint: .isDirectory)
  let result = await MLXStorageAdapter().scan(
    source: allowedSource(id: "real-mlx", provider: .mlx, root: root)
  )

  #expect(!result.installations.isEmpty)
  #expect(result.installations.allSatisfy { $0.providerID == .mlx })
  #expect(result.installations.allSatisfy { $0.variant.format == .mlx })
}

@Test("Hugging Face ignores Finder metadata at the snapshots root")
func huggingFaceIgnoresSnapshotRootMetadata() async throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  defer { try? FileManager.default.removeItem(at: root) }
  let repository = root.appending(path: "models--acme--model", directoryHint: .isDirectory)
  let revision = repository.appending(
    path: "snapshots/revision-1",
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(at: revision, withIntermediateDirectories: true)
  try Data("finder metadata".utf8).write(
    to: repository.appending(path: "snapshots/.DS_Store")
  )
  try Data("{}".utf8).write(to: revision.appending(path: "config.json"))

  let adapter = try HuggingFaceStorageAdapter()
  let result = await adapter.scan(
    source: allowedSource(id: "hf-metadata", provider: .huggingFace, root: root)
  )

  #expect(result.installations.count == 1)
  #expect(
    result.installations.first?.rootURL.resolvingSymlinksInPath()
      == revision.resolvingSymlinksInPath()
  )
  #expect(result.installations.first?.artifacts.map(\.url.lastPathComponent) == ["config.json"])
}

@Test("Opt-in real Hugging Face cache has no overlapping manual installation views")
func realHuggingFaceCacheHasNoManualDuplicates() async throws {
  guard let path = ProcessInfo.processInfo.environment["WTM_REAL_HF_CACHE"] else { return }
  let root = URL(filePath: path, directoryHint: .isDirectory)
  let registry = try AdapterRegistry(adapters: [
    try HuggingFaceStorageAdapter(),
    ManualFolderAdapter(),
  ])
  let snapshot = await InventoryCoordinator(registry: registry).scan(sources: [
    allowedSource(id: "real-manual-overlap", provider: .manual, root: root),
    allowedSource(id: "real-hugging-face", provider: .huggingFace, root: root),
  ])

  #expect(snapshot.installations.contains { $0.providerID == .huggingFace })
  #expect(
    !snapshot.installations.contains {
      $0.providerID == .huggingFace && $0.rootURL.lastPathComponent == "snapshots"
    }
  )
  if let gptOSS = snapshot.installations.first(where: {
    $0.identity.displayName == "gpt-oss-20b"
  }) {
    #expect(
      gptOSS.modelCard?.url.absoluteString == "https://huggingface.co/openai/gpt-oss-20b"
    )
  }
  if ProcessInfo.processInfo.environment["WTM_EXPECT_REAL_HF_PARTIAL"] == "1" {
    #expect(
      snapshot.installations.contains {
        $0.providerID == .huggingFace && $0.state == .incomplete
      }
    )
    #expect(snapshot.issues.contains { $0.code == "HF_DOWNLOAD_INCOMPLETE" })
  }
  let huggingFaceArtifactPaths = Set(
    snapshot.installations
      .filter { $0.providerID == .huggingFace }
      .flatMap(\.artifacts)
      .map { $0.url.standardizedFileURL.path }
  )
  let shadowManualInstallations = snapshot.installations.filter { installation in
    guard installation.providerID == .manual, !installation.artifacts.isEmpty else { return false }
    return Set(installation.artifacts.map { $0.url.standardizedFileURL.path })
      .isSubset(of: huggingFaceArtifactPaths)
  }
  #expect(shadowManualInstallations.isEmpty)
}

private func fixtureRoot(_ name: String) -> URL? {
  Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
}

private func allowedSource(id: String, provider: ProviderID, root: URL) -> ScanSource {
  let source = ScanSource(
    id: id,
    displayName: id,
    providerID: provider,
    rootURL: root,
    accessState: .allowed,
    isEnabled: true
  )
  guard let approved = try? SourceApprovalPolicy().approve(source) else {
    preconditionFailure("Fixture source must be approvable")
  }
  return approved
}

private struct TemporaryMLXFixture {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(
      path: "wtm-mlx-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  var source: ScanSource {
    allowedSource(id: "mlx-temporary", provider: .mlx, root: root)
  }

  func write(_ name: String, _ contents: String) throws {
    try Data(contents.utf8).write(to: root.appending(path: name))
  }

  func remove() {
    try? FileManager.default.removeItem(at: root)
  }
}
