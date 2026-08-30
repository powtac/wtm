import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

@testable import RuntimeLlamaCpp

private actor LlamaCppTransportStub: LlamaCppRuntimeTransport {
  let healthy: Bool
  let response: String
  private(set) var prompts: [String] = []

  init(healthy: Bool = true, response: String = "OK") {
    self.healthy = healthy
    self.response = response
  }

  func isHealthy(endpoint: URL) -> Bool { healthy }
  func complete(endpoint: URL, prompt: String) -> String {
    prompts.append(prompt)
    return response
  }
}

private func ggufInstallation() -> ModelInstallation {
  let modelURL = FileManager.default.temporaryDirectory.appending(
    path: "wtm-runtime-\(UUID().uuidString).gguf"
  )
  do {
    try minimalGGUF().write(to: modelURL)
  } catch {
    preconditionFailure("Failed to create test GGUF: \(error)")
  }
  let identity = ModelIdentity(id: "manual:tiny", displayName: "tiny")
  return ModelInstallation(
    id: "manual-source:tiny",
    identity: identity,
    variant: ModelVariant(id: "manual:tiny:gguf", identityID: identity.id, format: .gguf),
    sourceID: "manual-source",
    providerID: .manual,
    rootURL: modelURL,
    state: .stored,
    artifacts: [
      Artifact(
        id: "weights",
        url: modelURL,
        kind: .weights,
        logicalByteCount: 1_000,
        allocatedByteCount: 1_024
      )
    ]
  )
}

private func enabledLlamaDefinition() throws -> (ToolDefinition, ToolExecutionApproval) {
  let definition = ToolDefinition(
    id: UUID(),
    displayName: "llama.cpp",
    role: .runtime,
    origin: .userCreated,
    isEnabled: true,
    executableURL: URL(filePath: "/usr/bin/true"),
    arguments: [
      .literal("--model"), .placeholder(.modelPath),
      .literal("--host"), .literal("127.0.0.1"),
      .literal("--port"), .placeholder(.port),
    ],
    supportedFormats: [.gguf]
  )
  let validation = try ToolInvocationBuilder().inspect(definition)
  return (
    definition,
    ToolExecutionApproval(
      definition: definition,
      executableIdentity: validation.executableIdentity,
      approvedAt: .now
    )
  )
}

@Test("llama.cpp convention preserves the selected definition origin")
func llamaCppConventionPreservesOrigin() {
  let definition = LlamaCppToolConvention().definition(
    executableURL: URL(filePath: "/usr/bin/true"),
    origin: .userCreated
  )

  #expect(definition.origin == .userCreated)
}

@Test("llama.cpp plan binds one approved GGUF to numeric loopback")
func llamaCppPlanUsesApprovedLoopbackArguments() async throws {
  let (definition, approval) = try enabledLlamaDefinition()
  let model = ggufInstallation()
  let adapter = LlamaCppRuntimeAdapter(transport: LlamaCppTransportStub())
  let plan = try await adapter.makeTestPlan(
    for: model,
    context: RuntimeLaunchContext(
      port: 20_001,
      toolDefinition: definition,
      toolApproval: approval
    )
  )

  #expect(plan.endpoint.host == "127.0.0.1")
  #expect(plan.endpoint.port == 20_001)
  #expect(plan.stopBehavior == .stopOwnedProcess)
  guard case .executable(let invocation) = plan.strategy else {
    Issue.record("Expected executable plan")
    return
  }
  #expect(
    invocation.arguments == [
      "--model", model.rootURL.path, "--host", "127.0.0.1", "--port", "20001",
    ])
  #expect(invocation.protectedPathIdentities.count == 1)
}

@Test("llama.cpp rejects a definition that can bind beyond loopback")
func llamaCppRejectsUnsafeHostArguments() async throws {
  let (safeDefinition, _) = try enabledLlamaDefinition()
  let unsafeDefinition = ToolDefinition(
    id: safeDefinition.id,
    displayName: safeDefinition.displayName,
    role: safeDefinition.role,
    origin: safeDefinition.origin,
    isEnabled: true,
    executableURL: safeDefinition.executableURL,
    arguments: [
      .literal("--model"), .placeholder(.modelPath),
      .literal("--host"), .literal("0.0.0.0"),
      .literal("--port"), .placeholder(.port),
    ],
    supportedFormats: [.gguf]
  )
  let unsafeValidation = try ToolInvocationBuilder().inspect(unsafeDefinition)
  let unsafeApproval = ToolExecutionApproval(
    definition: unsafeDefinition,
    executableIdentity: unsafeValidation.executableIdentity,
    approvedAt: .now
  )
  let adapter = LlamaCppRuntimeAdapter(transport: LlamaCppTransportStub())

  await #expect(throws: RuntimeAdapterError.invalidToolDefinition) {
    _ = try await adapter.makeTestPlan(
      for: ggufInstallation(),
      context: RuntimeLaunchContext(
        port: 20_001,
        toolDefinition: unsafeDefinition,
        toolApproval: unsafeApproval
      )
    )
  }
}

@Test("llama.cpp readiness reports memory pressure as estimate, not runtime proof")
func llamaCppReadinessSeparatesMemoryEstimate() async throws {
  let (definition, approval) = try enabledLlamaDefinition()
  let adapter = LlamaCppRuntimeAdapter(
    configuredDefinition: definition,
    configuredApproval: approval,
    transport: LlamaCppTransportStub()
  )

  let readiness = await adapter.readiness(
    for: ggufInstallation(),
    environment: RuntimeEnvironment(architecture: "arm64", memoryCapacityByteCount: 1)
  )

  #expect(readiness.compatibility.value == .insufficientMemory)
  #expect(readiness.validation.value == .staticCompatible)
  #expect(readiness.runtime.value == .stopped)
  #expect(readiness.estimatedMemory?.basis.contains("estimate only") == true)
}

@Test("llama.cpp readiness rejects an unsupported architecture")
func llamaCppReadinessChecksArchitecture() async throws {
  let (definition, approval) = try enabledLlamaDefinition()
  let adapter = LlamaCppRuntimeAdapter(
    configuredDefinition: definition,
    configuredApproval: approval,
    transport: LlamaCppTransportStub()
  )

  let readiness = await adapter.readiness(
    for: ggufInstallation(),
    environment: RuntimeEnvironment(architecture: "x86_64")
  )

  #expect(readiness.compatibility.value == .unsupportedArchitecture)
  #expect(readiness.validation.value == .blocked)
}

@Test("llama.cpp rejects a tensorless GGUF vocabulary file")
func llamaCppRejectsVocabularyGGUF() async throws {
  let modelURL = FileManager.default.temporaryDirectory.appending(
    path: "wtm-runtime-vocab-\(UUID().uuidString).gguf"
  )
  defer { try? FileManager.default.removeItem(at: modelURL) }
  try tensorlessGGUF().write(to: modelURL)

  let identity = ModelIdentity(id: "manual:vocab", displayName: "vocab")
  let installation = ModelInstallation(
    id: "manual:vocab",
    identity: identity,
    variant: ModelVariant(id: "manual:vocab:gguf", identityID: identity.id, format: .gguf),
    sourceID: "manual",
    providerID: .manual,
    rootURL: modelURL,
    state: .stored,
    artifacts: [
      Artifact(
        id: "vocab",
        url: modelURL,
        kind: .weights,
        logicalByteCount: 24,
        allocatedByteCount: 24
      )
    ]
  )
  let readiness = await LlamaCppRuntimeAdapter().readiness(
    for: installation,
    environment: RuntimeEnvironment(architecture: "arm64")
  )

  #expect(readiness.compatibility.value == .invalidModel)
  #expect(readiness.validation.value == .blocked)
}

@Test("llama.cpp inference result requires a completed model request")
func llamaCppInferenceUsesMinimalCompletion() async {
  let transport = LlamaCppTransportStub(response: "O")
  let adapter = LlamaCppRuntimeAdapter(transport: transport)
  let result = await adapter.inferenceCheck(
    endpoint: llamaTestEndpoint(),
    installation: ggufInstallation(),
    prompt: "OK?"
  )

  #expect(result.succeeded)
  #expect(await transport.prompts == ["OK?"])
}

private func llamaTestEndpoint() -> URL {
  var components = URLComponents()
  components.scheme = "http"
  components.host = "127.0.0.1"
  components.port = 20_001
  guard let url = components.url else { preconditionFailure("Valid test endpoint") }
  return url
}

private func minimalGGUF() -> Data {
  var data = Data("GGUF".utf8)
  appendLittleEndian(UInt32(3), to: &data)
  appendLittleEndian(UInt64(1), to: &data)
  appendLittleEndian(UInt64(0), to: &data)
  return data
}

private func tensorlessGGUF() -> Data {
  var data = Data("GGUF".utf8)
  appendLittleEndian(UInt32(3), to: &data)
  appendLittleEndian(UInt64(0), to: &data)
  appendLittleEndian(UInt64(0), to: &data)
  return data
}

private func appendLittleEndian(_ value: UInt32, to data: inout Data) {
  for shift in stride(from: 0, through: 24, by: 8) {
    data.append(UInt8((value >> UInt32(shift)) & 0xff))
  }
}

private func appendLittleEndian(_ value: UInt64, to data: inout Data) {
  for shift in stride(from: 0, through: 56, by: 8) {
    data.append(UInt8((value >> UInt64(shift)) & 0xff))
  }
}
