import AdapterHuggingFace
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
  ScanSource(
    id: id,
    displayName: id,
    providerID: provider,
    rootURL: root,
    accessState: .allowed,
    isEnabled: true
  )
}
