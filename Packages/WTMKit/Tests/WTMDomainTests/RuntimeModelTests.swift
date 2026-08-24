import Foundation
import Testing

@testable import WTMDomain

@Test("Runtime observations expire only at their explicit deadline")
func runtimeObservationExpirationIsExplicit() {
  let checkedAt = Date(timeIntervalSince1970: 100)
  let observation = RuntimeObservation(
    value: ModelValidation.runtimeReachable,
    adapterID: .ollama,
    adapterVersion: "1",
    checkedAt: checkedAt,
    expiresAt: Date(timeIntervalSince1970: 200),
    evidence: "GET /api/tags"
  )

  #expect(!observation.isExpired(at: Date(timeIntervalSince1970: 199)))
  #expect(observation.isExpired(at: Date(timeIntervalSince1970: 200)))
}

@Test("Tool arguments preserve typed placeholders through JSON")
func toolArgumentsRoundTripWithoutInterpolation() throws {
  let definition = ToolDefinition(
    id: UUID(),
    displayName: "llama.cpp",
    role: .runtime,
    origin: .userCreated,
    isEnabled: false,
    executableURL: URL(filePath: "/opt/homebrew/bin/llama-server"),
    arguments: [.literal("--model"), .placeholder(.modelPath)],
    supportedFormats: [.gguf]
  )

  let decoded = try JSONDecoder().decode(
    ToolDefinition.self,
    from: JSONEncoder().encode(definition)
  )

  #expect(decoded == definition)
  #expect(decoded.arguments == [.literal("--model"), .placeholder(.modelPath)])
}

@Test("Runtime instance ownership is independent from running state")
func runtimeOwnershipIsNotInferredFromState() {
  let instance = RuntimeInstance(
    id: UUID(),
    adapterID: .ollama,
    installationID: "ollama:model",
    externalIdentifier: "model:latest",
    endpoint: URL(string: "http://127.0.0.1:11434")!,
    state: .running,
    startedAt: nil,
    ownership: .providerManaged
  )

  #expect(instance.state == .running)
  #expect(instance.ownership == .providerManaged)
}
