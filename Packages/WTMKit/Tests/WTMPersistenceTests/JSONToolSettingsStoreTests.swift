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
