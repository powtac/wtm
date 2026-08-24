import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain

@testable import RuntimeOllama

private actor OllamaRuntimeTransportStub: OllamaRuntimeTransport {
  let available: Set<String>
  let running: Set<String>
  let response: String
  private(set) var generatedModels: [String] = []

  init(available: Set<String>, running: Set<String>, response: String = "OK") {
    self.available = available
    self.running = running
    self.response = response
  }

  func availableModelNames() -> Set<String> { available }
  func runningModelNames() -> Set<String> { running }
  func generate(model: String, prompt: String) -> String {
    generatedModels.append(model)
    return response
  }
}

private func ollamaInstallation() -> ModelInstallation {
  let identity = ModelIdentity(id: "ollama:tiny", displayName: "tiny")
  return ModelInstallation(
    id: "ollama-source:tiny",
    identity: identity,
    variant: ModelVariant(id: "ollama:tiny:latest", identityID: identity.id, format: .ollama),
    sourceID: "ollama-source",
    providerID: .ollama,
    rootURL: URL(
      filePath: "/tmp/models/manifests/registry.ollama.ai/library/tiny/latest"
    ),
    state: .stored,
    artifacts: [
      Artifact(
        id: "blob",
        url: URL(filePath: "/tmp/blob"),
        kind: .weights,
        logicalByteCount: 1_000,
        allocatedByteCount: 1_024
      )
    ]
  )
}

private func ollamaEndpoint() -> URL {
  var components = URLComponents()
  components.scheme = "http"
  components.host = "127.0.0.1"
  components.port = 11_434
  guard let url = components.url else { preconditionFailure("Valid test endpoint") }
  return url
}

@Test("Ollama readiness keeps API reachability separate from inference verification")
func ollamaReadinessUsesSeparateAxes() async {
  let transport = OllamaRuntimeTransportStub(
    available: ["tiny:latest"],
    running: ["tiny:latest"]
  )
  let adapter = OllamaRuntimeAdapter(endpoint: ollamaEndpoint(), transport: transport)

  let readiness = await adapter.readiness(
    for: ollamaInstallation(),
    environment: RuntimeEnvironment(architecture: "arm64")
  )

  #expect(readiness.compatibility.value == .compatible)
  #expect(readiness.validation.value == .runtimeReachable)
  #expect(readiness.runtime.value == .running)
  #expect(readiness.validation.value != .inferenceVerified)
}

@Test("Ollama test plan is provider-managed and cannot claim Stop ownership")
func ollamaPlanNeverClaimsProcessOwnership() async throws {
  let transport = OllamaRuntimeTransportStub(available: ["tiny:latest"], running: [])
  let adapter = OllamaRuntimeAdapter(endpoint: ollamaEndpoint(), transport: transport)
  let installation = ollamaInstallation()

  let plan = try await adapter.makeTestPlan(
    for: installation,
    context: RuntimeLaunchContext()
  )

  #expect(plan.stopBehavior == .providerStopUnavailable)
  guard case .providerManaged(_, let identifier) = plan.strategy else {
    Issue.record("Expected a provider-managed plan")
    return
  }
  #expect(identifier == "tiny:latest")
}

@Test("Ollama inference uses the manifest-derived provider model name")
func ollamaInferenceUsesProviderIdentity() async {
  let transport = OllamaRuntimeTransportStub(available: ["tiny:latest"], running: [])
  let adapter = OllamaRuntimeAdapter(endpoint: ollamaEndpoint(), transport: transport)

  let result = await adapter.inferenceCheck(
    endpoint: ollamaEndpoint(),
    installation: ollamaInstallation(),
    prompt: "OK?"
  )

  #expect(result.succeeded)
  #expect(await transport.generatedModels == ["tiny:latest"])
}
