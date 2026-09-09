import Foundation
import RuntimeLocalAI
import Testing
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

@Test("LocalAI requires explicit mappings and does not infer them from filenames")
func localAINoImplicitMapping() async {
  let adapter = LocalAIRuntimeAdapter(connection: { _ in nil })
  let readiness = await adapter.readiness(
    for: localModel(), environment: RuntimeEnvironment(architecture: "arm64"))
  #expect(readiness.validation.value == .blocked)
}

@Test("LocalAI uses exact model IDs and never offers provider Stop")
func localAIExplicitContract() async throws {
  let api = LocalAITestTransport()
  let adapter = LocalAIRuntimeAdapter(
    connection: { _ in localConnection() }, transport: { _ in api })
  let model = localModel()
  let readiness = await adapter.readiness(
    for: model, environment: RuntimeEnvironment(architecture: "arm64"))
  #expect(readiness.validation.value == .runtimeReachableUnauthenticated)
  #expect(readiness.runtime.value == .stopped)
  let plan = try await adapter.makeTestPlan(for: model, context: RuntimeLaunchContext())
  #expect(plan.stopBehavior == .providerStopUnavailable)
  #expect(
    plan.strategy
      == .providerManaged(endpoint: localConnection().endpoint, externalIdentifier: "EXACT-id"))
  #expect(await adapter.inferenceCheck(plan: plan, installation: model, prompt: "OK").succeeded)
  #expect(await api.requestedModel == "EXACT-id")
}

@Test("LocalAI rejects stale model bindings, partial weights and external endpoints")
func localAIFailClosed() async throws {
  let api = LocalAITestTransport()
  let adapter = LocalAIRuntimeAdapter(
    connection: { _ in localConnection() }, transport: { _ in api })
  let model = localModel()
  let plan = RuntimeTestPlan(
    id: UUID(), adapterID: .localAI, installationID: model.id, createdAt: .now,
    expiresAt: Date.now.addingTimeInterval(60), endpoint: localConnection().endpoint,
    strategy: .providerManaged(
      endpoint: localConnection().endpoint, externalIdentifier: "different"),
    stopBehavior: .providerStopUnavailable)
  #expect(
    await adapter.inferenceCheck(plan: plan, installation: model, prompt: "OK").succeeded == false)
  #expect(await api.requestedModel == nil)
  let external = LocalAIRuntimeAdapter(connection: { _ in
    LocalModelConnection(
      endpoint: localAITestURL("http://example.com:8080"), modelReference: "EXACT-id")
  })
  await #expect(throws: (any Error).self) {
    try await external.makeTestPlan(for: model, context: RuntimeLaunchContext())
  }
  let partialReadiness = await adapter.readiness(
    for: localModel(partial: true), environment: RuntimeEnvironment(architecture: "arm64"))
  #expect(partialReadiness.integrity.value == .partial)
  #expect(partialReadiness.validation.value == .blocked)
  await #expect(throws: (any Error).self) {
    try await adapter.makeTestPlan(for: localModel(partial: true), context: RuntimeLaunchContext())
  }
}

private actor LocalAITestTransport: LocalAIRuntimeTransport {
  var requestedModel: String?
  func health() {}
  func models() -> Set<String> { ["EXACT-id"] }
  func generate(model: String, prompt: String) -> String { requestedModel = model; return "OK" }
}

private func localConnection() -> LocalModelConnection {
  LocalModelConnection(
    endpoint: localAITestURL("http://127.0.0.1:8080"), modelReference: "EXACT-id")
}
private func localModel(partial: Bool = false) -> ModelInstallation {
  ModelInstallation(
    id: "model", identity: ModelIdentity(id: "tiny", displayName: "Filename is not API identity"),
    variant: ModelVariant(id: "tiny", identityID: "tiny", format: .gguf), sourceID: "source",
    providerID: .manual,
    rootURL: URL(filePath: "/fixture/model.gguf"), state: .stored,
    artifacts: [
      Artifact(
        id: "weight", url: URL(filePath: "/fixture/model.gguf"), kind: .weights,
        logicalByteCount: 24, allocatedByteCount: 24, isPartial: partial)
    ])
}

private func localAITestURL(_ value: String) -> URL {
  guard let url = URL(string: value) else { preconditionFailure("Invalid test URL") }
  return url
}
