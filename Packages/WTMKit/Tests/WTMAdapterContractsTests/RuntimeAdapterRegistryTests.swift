import Foundation
import Testing
import WTMDomain

@testable import WTMAdapterContracts

private struct StubRuntimeAdapter: RuntimeAdapter {
  let id: RuntimeAdapterID
  let displayName = "Stub"
  let version = "1"
  let supportedFormats: Set<ModelFormat> = [.gguf]

  func readiness(
    for installation: ModelInstallation,
    environment: RuntimeEnvironment
  ) async -> RuntimeReadiness {
    fatalError("Not used by registry tests")
  }

  func makeTestPlan(
    for installation: ModelInstallation,
    context: RuntimeLaunchContext
  ) async throws -> RuntimeTestPlan {
    fatalError("Not used by registry tests")
  }

  func healthCheck(endpoint: URL) async -> RuntimeProbeResult {
    fatalError("Not used by registry tests")
  }

  func inferenceCheck(
    endpoint: URL,
    installation: ModelInstallation,
    prompt: String
  ) async -> RuntimeProbeResult {
    fatalError("Not used by registry tests")
  }
}

@Test("Runtime registry rejects duplicate capability IDs")
func duplicateRuntimeIDsAreRejected() {
  #expect(throws: RuntimeAdapterRegistryError.duplicateRuntime(.ollama)) {
    _ = try RuntimeAdapterRegistry(
      adapters: [
        StubRuntimeAdapter(id: .ollama),
        StubRuntimeAdapter(id: .ollama),
      ]
    )
  }
}

@Test("Runtime registry keeps runtime IDs separate from storage providers")
func runtimeRegistryResolvesByRuntimeID() throws {
  let registry = try RuntimeAdapterRegistry(
    adapters: [StubRuntimeAdapter(id: .llamaCpp)]
  )

  #expect(registry.runtimeIDs == [.llamaCpp])
  #expect(registry.adapter(for: .llamaCpp)?.displayName == "Stub")
  #expect(registry.adapter(for: .ollama) == nil)
}
