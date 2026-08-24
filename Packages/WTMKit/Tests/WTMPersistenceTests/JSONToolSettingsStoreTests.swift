import Foundation
import Testing
import WTMDomain
import WTMRuntime

@testable import WTMPersistence

@Test("Tool settings persist definitions and approvals but no runtime state or logs")
func toolSettingsRoundTrip() async throws {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "wtm-tool-settings-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = JSONToolSettingsStore(
    settingsURL: directory.appending(path: "tools.json")
  )
  let definition = ToolDefinition(
    id: UUID(),
    displayName: "llama.cpp",
    role: .runtime,
    origin: .userCreated,
    isEnabled: true,
    executableURL: URL(filePath: "/usr/bin/true"),
    arguments: [.literal("--model"), .placeholder(.modelPath)],
    supportedFormats: [.gguf]
  )
  let validation = try ToolInvocationBuilder().inspect(definition)
  let approval = ToolExecutionApproval(
    definition: definition,
    executableIdentity: validation.executableIdentity,
    approvedAt: .now
  )
  let snapshot = ToolSettingsSnapshot(
    revision: 1,
    definitions: [definition],
    approvals: [approval]
  )

  try await store.save(snapshot)
  let loaded = try #require(try await store.load())

  #expect(loaded == snapshot)
  let data = try Data(contentsOf: directory.appending(path: "tools.json"))
  let json = try #require(String(data: data, encoding: .utf8))
  #expect(!json.contains("RuntimeInstance"))
  #expect(!json.contains("standardOutput"))
}

@Test("Tool manifests import disabled and export without home paths or approvals")
func toolManifestPolicy() throws {
  let originalID = UUID()
  let importedID = UUID()
  let homeURL = URL(filePath: "/tmp/wtm-test-home", directoryHint: .isDirectory)
  let definition = ToolDefinition(
    id: originalID,
    displayName: "llama.cpp",
    role: .runtime,
    runtimeAdapterID: RuntimeAdapterID(rawValue: "runtime.llama-cpp"),
    origin: .userCreated,
    isEnabled: true,
    executableURL: homeURL.appending(path: "bin/llama-server"),
    arguments: [
      .literal("--model"),
      .literal("/tmp/wtm-test-home/Models/model.gguf"),
      .placeholder(.port),
    ],
    supportedFormats: [.gguf],
    currentDirectoryURL: homeURL.appending(path: "Models", directoryHint: .isDirectory),
    environment: [
      "SAFE": "1",
      "PRIVATE_PATH": "/tmp/wtm-test-home/.cache",
    ]
  )

  let imported = ToolDefinitionManifestPolicy.definitionForImport(definition, id: importedID)
  #expect(imported.id == importedID)
  #expect(imported.origin == .imported)
  #expect(!imported.isEnabled)
  #expect(imported.lastValidation == nil)

  let exported = ToolDefinitionManifestPolicy.definitionForExport(
    definition,
    homeDirectoryURL: homeURL
  )
  let data = try JSONEncoder().encode(ToolDefinitionManifest(definition: exported))
  let json = try #require(String(data: data, encoding: .utf8))
  #expect(!exported.isEnabled)
  #expect(exported.currentDirectoryURL == nil)
  #expect(exported.environment == ["SAFE": "1"])
  #expect(exported.executableURL.path == "/path/to/llama-server")
  #expect(!json.contains("/tmp/wtm-test-home"))

  let manifest = try JSONDecoder().decode(ToolDefinitionManifest.self, from: data)
  #expect(manifest.schemaVersion == ToolDefinitionManifest.currentSchemaVersion)
  #expect(manifest.definition == exported)
}
