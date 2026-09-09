import AdapterGPT4All
import AdapterJan
import Foundation
import Testing
import WTMDomain
import WTMInventory

@Test("GPT4All recognizes flat GGUF, partial prefixes, and excludes remote credentials")
func gpt4AllStorageContract() async throws {
  let fixture = try DesktopStorageFixture()
  defer { fixture.remove() }
  try fixture.write("tiny.gguf", fixture.gguf)
  try fixture.write("incomplete-large.gguf", Data([0, 1]))
  try fixture.write("legacy.bin", Data([0]))
  try fixture.write("fake.gguf", Data("fake".utf8))
  try fixture.write("api.rmodel", Data(#"{"apiKey":"synthetic-not-a-secret"}"#.utf8))
  let result = await GPT4AllStorageAdapter().scan(source: try fixture.source(.gpt4All))
  #expect(result.installations.count == 3)
  #expect(result.installations.filter { $0.state == .stored }.count == 1)
  #expect(
    result.installations.contains {
      $0.state == .incomplete && $0.artifacts.first?.isPartial == true
    })
  #expect(!result.installations.flatMap(\.artifacts).contains { $0.url.pathExtension == "rmodel" })
  #expect(result.issues.contains { $0.code == "GPT4ALL_FILE_UNVERIFIED" })
}

@Test("GPT4All rejects escaped symlinks and preserves hard-link identity")
func gpt4AllScopedLinks() async throws {
  let fixture = try DesktopStorageFixture()
  let outside = try DesktopStorageFixture()
  defer { fixture.remove(); outside.remove() }
  try fixture.write("tiny.gguf", fixture.gguf)
  try outside.write("outside.gguf", outside.gguf)
  try FileManager.default.linkItem(
    at: fixture.root.appending(path: "tiny.gguf"), to: fixture.root.appending(path: "copy.gguf"))
  try FileManager.default.createSymbolicLink(
    at: fixture.root.appending(path: "escape.gguf"),
    withDestinationURL: outside.root.appending(path: "outside.gguf"))
  let result = await GPT4AllStorageAdapter().scan(source: try fixture.source(.gpt4All))
  #expect(result.installations.count == 2)
  #expect(
    Set(result.installations.flatMap(\.artifacts).compactMap(\.physicalIdentifier)).count == 1)
}

@Test("Jan validates documented model metadata against local GGUF and size")
func janManifestContract() async throws {
  let fixture = try DesktopStorageFixture()
  defer { fixture.remove() }
  try fixture.write("llamacpp/models/org/tiny/model.gguf", fixture.gguf)
  try fixture.write("llamacpp/models/org/tiny/model.yml", Data(fixture.manifest.utf8))
  let source = try fixture.source(.jan)
  let result = await JanStorageAdapter().scan(source: source)
  #expect(result.installations.first?.state == .stored)
  #expect(result.installations.first?.variant.format == .gguf)
  try fixture.write("llamacpp/models/org/tiny/model.gguf", Data([0]))
  let broken = await JanStorageAdapter().scan(source: source)
  #expect(!broken.installations.contains { $0.state == .stored })
  #expect(!broken.issues.isEmpty)
}

@Test("Jan rejects manifest traversal, YAML aliases, future schemas and missing weights")
func janUnsupportedMetadata() async throws {
  let fixture = try DesktopStorageFixture()
  defer { fixture.remove() }
  for manifest in [
    fixture.manifest.replacingOccurrences(
      of: "llamacpp/models/org/tiny/model.gguf", with: "../../outside.gguf"),
    fixture.manifest + "future_schema: 2\n",
    fixture.manifest.replacingOccurrences(of: "name: tiny", with: "name: &alias tiny"),
  ] {
    try fixture.write("llamacpp/models/org/tiny/model.yml", Data(manifest.utf8))
    let result = await JanStorageAdapter().scan(source: try fixture.source(.jan))
    #expect(result.installations.isEmpty)
    #expect(!result.issues.isEmpty)
  }
  try fixture.write("llamacpp/models/org/tiny/model.yml", Data(fixture.manifest.utf8))
  let missing = await JanStorageAdapter().scan(source: try fixture.source(.jan))
  #expect(missing.installations.first?.state == .incomplete)
}

private struct DesktopStorageFixture {
  let root: URL
  var gguf: Data {
    Data(Array("GGUF".utf8) + [3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  }
  var manifest: String {
    "model_path: llamacpp/models/org/tiny/model.gguf\nname: tiny\nsize_bytes: 24\nembedding: false\n"
  }
  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "wtm-desktop-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  func write(_ path: String, _ data: Data) throws {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
  }
  func source(_ provider: ProviderID) throws -> ScanSource {
    try SourceApprovalPolicy().approve(
      ScanSource(id: "fixture", displayName: "Fixture", providerID: provider, rootURL: root))
  }
  func remove() { try? FileManager.default.removeItem(at: root) }
}
