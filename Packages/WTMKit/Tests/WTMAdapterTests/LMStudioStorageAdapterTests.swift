import AdapterLMStudio
import Foundation
import Testing
import WTMDomain
import WTMInventory

@Test("LM Studio uses its import layout and validates GGUF contents")
func lmStudioImportContract() async throws {
  let fixture = try LMStudioFixture()
  defer { fixture.remove() }
  try fixture.writeGGUF("publisher/model/tiny-Q4_K_M.gguf")
  try Data("not a model".utf8).write(to: fixture.root.appending(path: "publisher/model/fake.gguf"))

  let result = await LMStudioStorageAdapter().scan(source: try fixture.source)

  let model = try #require(result.installations.first)
  #expect(result.installations.count == 1)
  #expect(model.providerID == .lmStudio)
  #expect(model.variant.format == .gguf)
  #expect(model.variant.quantization == "Q4_K_M")
  #expect(model.state == .stored)
  #expect(model.modelCard == nil)
  #expect(model.artifacts.first?.physicalIdentifier != nil)
}

@Test("LM Studio does not confirm loose files or split-model completeness")
func lmStudioUnknownLayouts() async throws {
  let fixture = try LMStudioFixture()
  defer { fixture.remove() }
  try fixture.writeGGUF("loose.gguf")
  try fixture.writeGGUF("publisher/model/tiny-00001-of-00002.gguf")

  let result = await LMStudioStorageAdapter().scan(source: try fixture.source)

  #expect(result.installations.count == 2)
  #expect(result.installations.allSatisfy { $0.variant.format == .unknown && $0.state == .issue })
  #expect(result.issues.count == 2)
}

@Test("LM Studio partial artifacts remain incomplete and unknown")
func lmStudioPartialContract() async throws {
  let fixture = try LMStudioFixture()
  defer { fixture.remove() }
  try fixture.writeGGUF("publisher/model/model.gguf.incomplete")

  let result = await LMStudioStorageAdapter().scan(source: try fixture.source)

  let model = try #require(result.installations.first)
  #expect(model.state == .incomplete)
  #expect(model.variant.format == .unknown)
  #expect(model.artifacts.first?.isPartial == true)
}

@Test("LM Studio retains shared physical identity and rejects links outside consent")
func lmStudioLinksStayScoped() async throws {
  let fixture = try LMStudioFixture()
  let outside = try LMStudioFixture()
  defer { fixture.remove(); outside.remove() }
  try fixture.writeGGUF("publisher/model/model.gguf")
  try outside.writeGGUF("outside.gguf")
  let model = fixture.root.appending(path: "publisher/model/model.gguf")
  try FileManager.default.linkItem(
    at: model, to: fixture.root.appending(path: "publisher/model/copy.gguf"))
  try FileManager.default.createSymbolicLink(
    at: fixture.root.appending(path: "publisher/model/escape.gguf"),
    withDestinationURL: outside.root.appending(path: "outside.gguf")
  )

  let result = await LMStudioStorageAdapter().scan(source: try fixture.source)

  #expect(result.installations.count == 2)
  #expect(
    Set(result.installations.flatMap(\.artifacts).compactMap(\.physicalIdentifier)).count == 1)
}

private struct LMStudioFixture {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "wtm-lmstudio-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  var source: ScanSource {
    get throws {
      try SourceApprovalPolicy().approve(
        ScanSource(
          id: "lm-studio-fixture", displayName: "LM Studio", providerID: .lmStudio, rootURL: root)
      )
    }
  }

  func writeGGUF(_ path: String) throws {
    let url = root.appending(path: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = Data("GGUF".utf8)
    data.append(contentsOf: [3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    try data.write(to: url)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}
