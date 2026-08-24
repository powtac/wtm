import AdapterHuggingFace
import AdapterManual
import AdapterOllama
import Foundation
import Testing
import WTMDomain

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

  #expect(result.installations.count == 1)
  #expect(result.installations.first?.identity.family == "acme/tiny")
  #expect(
    result.installations.first?.modelCard?.url.absoluteString == "https://huggingface.co/acme/tiny")
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
