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

  let result = await HuggingFaceStorageAdapter().scan(source: source)

  #expect(result.installations.count == 2)
  let tiny = try #require(result.installations.first { $0.identity.family == "acme/tiny" })
  #expect(tiny.identity.family == "acme/tiny")
  #expect(
    tiny.modelCard?.url.absoluteString == "https://huggingface.co/acme/tiny")
  #expect(result.installations.contains { $0.state == .incomplete })
  #expect(result.issues.contains { $0.code == "HF_DOWNLOAD_INCOMPLETE" })
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

@Test("Opt-in real Hugging Face cache has no overlapping manual installation views")
func realHuggingFaceCacheHasNoManualDuplicates() async throws {
  guard let path = ProcessInfo.processInfo.environment["WTM_REAL_HF_CACHE"] else { return }
  let root = URL(filePath: path, directoryHint: .isDirectory)
  let registry = try AdapterRegistry(adapters: [
    HuggingFaceStorageAdapter(),
    ManualFolderAdapter(),
  ])
  let snapshot = await InventoryCoordinator(registry: registry).scan(sources: [
    allowedSource(id: "real-manual-overlap", provider: .manual, root: root),
    allowedSource(id: "real-hugging-face", provider: .huggingFace, root: root),
  ])

  #expect(snapshot.installations.contains { $0.providerID == .huggingFace })
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
