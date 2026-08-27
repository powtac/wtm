import Darwin
import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain

@testable import WTMRuntime

private actor FakeProcessHandle: RuntimeProcessHandle {
  private let ignoresTermination: Bool
  private var running = true
  private var terminated = false

  init(ignoresTermination: Bool = false) {
    self.ignoresTermination = ignoresTermination
  }

  func processIdentifier() async -> Int32 { 42 }
  func isRunning() async -> Bool { running }
  func terminate() async {
    terminated = true
    if !ignoresTermination { running = false }
  }
  func waitForExit() async -> Int32 { 0 }
  func wasTerminated() -> Bool { terminated }
}

private final class FakeProcessLauncher: RuntimeProcessLaunching, @unchecked Sendable {
  let handle: FakeProcessHandle

  init(ignoresTermination: Bool = false) {
    handle = FakeProcessHandle(ignoresTermination: ignoresTermination)
  }

  func launch(
    _ invocation: RuntimeExecutableInvocation,
    outputHandler: @escaping RuntimeProcessOutputHandler
  ) throws -> any RuntimeProcessHandle {
    outputHandler(.standardError, "token=secret-value\nready\n")
    return handle
  }
}

private struct FakeEndpointCorrelator: RuntimeEndpointCorrelating {
  let result: Bool

  func ownsListener(processIdentifier: Int32, endpoint: URL) async -> Bool { result }
}

private struct FakeRuntimeAdapter: RuntimeAdapter {
  let id: RuntimeAdapterID
  let displayName = "Fake Runtime"
  let version = "1"
  let supportedFormats: Set<ModelFormat> = [.gguf]
  let healthSucceeds: Bool
  let inferenceSucceeds: Bool

  func readiness(
    for installation: ModelInstallation,
    environment: RuntimeEnvironment
  ) async -> RuntimeReadiness {
    fatalError("Not needed")
  }

  func makeTestPlan(
    for installation: ModelInstallation,
    context: RuntimeLaunchContext
  ) async throws -> RuntimeTestPlan {
    fatalError("Not needed")
  }

  func healthCheck(endpoint: URL) async -> RuntimeProbeResult {
    RuntimeProbeResult(
      succeeded: healthSucceeds,
      checkedAt: .now,
      summary: healthSucceeds ? "Healthy" : "Loading"
    )
  }

  func inferenceCheck(
    endpoint: URL,
    installation: ModelInstallation,
    prompt: String
  ) async -> RuntimeProbeResult {
    RuntimeProbeResult(
      succeeded: inferenceSucceeds,
      checkedAt: .now,
      summary: inferenceSucceeds ? "Verified" : "Inference failed"
    )
  }
}

private func runtimeInstallation() -> ModelInstallation {
  let identity = ModelIdentity(id: "manual:model", displayName: "Model")
  return ModelInstallation(
    id: "source:model",
    identity: identity,
    variant: ModelVariant(id: "manual:model:gguf", identityID: identity.id, format: .gguf),
    sourceID: "source",
    providerID: .manual,
    rootURL: URL(filePath: "/tmp/model.gguf"),
    state: .stored,
    artifacts: []
  )
}

private func executablePlan(
  installation: ModelInstallation,
  identity: ExecutableIdentity
) -> RuntimeTestPlan {
  let endpoint = brokerURL(port: 19_001)
  return RuntimeTestPlan(
    id: UUID(),
    adapterID: .llamaCpp,
    installationID: installation.id,
    createdAt: .now,
    expiresAt: .now.addingTimeInterval(60),
    endpoint: endpoint,
    strategy: .executable(
      RuntimeExecutableInvocation(
        executableURL: identity.canonicalURL,
        arguments: [],
        approvedIdentity: identity
      )
    ),
    stopBehavior: .stopOwnedProcess
  )
}

@Test("Broker starts, verifies, redacts logs, and stops only its process handle")
func ownedProcessLifecycle() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .llamaCpp,
    healthSucceeds: true,
    inferenceSucceeds: true
  )
  let launcher = FakeProcessLauncher()
  let registry = try RuntimeAdapterRegistry(adapters: [adapter])
  let broker = RuntimeBroker(
    registry: registry,
    launcher: launcher,
    endpointCorrelator: FakeEndpointCorrelator(result: true)
  )
  let installation = runtimeInstallation()
  let identity = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity

  let started = try await broker.start(
    plan: executablePlan(installation: installation, identity: identity),
    installation: installation,
    verifyInference: true,
    timeout: .seconds(1),
    pollInterval: .milliseconds(1)
  )
  #expect(started.instance.state == .running)
  #expect(started.instance.ownership == .startedByWTM)
  #expect(started.inference?.succeeded == true)

  let current = try await broker.snapshot(for: started.instance.id)
  #expect(current.logs.contains { $0.message.contains("<redacted>") })
  #expect(!current.logs.contains { $0.message.contains("secret-value") })

  let stopped = try await broker.stop(started.instance.id, timeout: .seconds(1))
  #expect(stopped.instance.state == .stopped)
  #expect(await launcher.handle.wasTerminated())
}

@Test("Runtime log redaction covers invocation paths and environment values")
func runtimeLogRedactsInvocationPaths() throws {
  let executableURL = URL(filePath: "/usr/bin/true")
  let identity = try ExecutableInspector().inspect(executableURL).identity
  let invocation = RuntimeExecutableInvocation(
    executableURL: executableURL,
    arguments: ["--model", "/tmp/private-model.gguf"],
    currentDirectoryURL: URL(filePath: "/tmp/private-working-directory"),
    environment: ["HOME": "/Users/private-user"],
    approvedIdentity: identity
  )

  let redacted = RuntimeLogRedactor(invocation: invocation).redact(
    "exe=/usr/bin/true model=/tmp/private-model.gguf cwd=/tmp/private-working-directory "
      + "home=/Users/private-user"
  )

  #expect(!redacted.contains("/usr/bin/true"))
  #expect(!redacted.contains("/tmp/private-model.gguf"))
  #expect(!redacted.contains("/tmp/private-working-directory"))
  #expect(!redacted.contains("/Users/private-user"))
}

@Test("Healthy spoof listener cannot verify a WTM-owned runtime")
func listenerMustBelongToOwnedProcess() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .llamaCpp,
    healthSucceeds: true,
    inferenceSucceeds: true
  )
  let launcher = FakeProcessLauncher()
  let broker = RuntimeBroker(
    registry: try RuntimeAdapterRegistry(adapters: [adapter]),
    launcher: launcher,
    endpointCorrelator: FakeEndpointCorrelator(result: false)
  )
  let installation = runtimeInstallation()
  let identity = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity

  await #expect(throws: RuntimeBrokerError.endpointOwnershipMismatch) {
    _ = try await broker.start(
      plan: executablePlan(installation: installation, identity: identity),
      installation: installation,
      verifyInference: true,
      timeout: .seconds(1),
      pollInterval: .milliseconds(1)
    )
  }
  #expect(await launcher.handle.wasTerminated())
}

@Test("Termination cleanup stops every WTM-owned process")
func terminationCleanupStopsOwnedProcesses() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .llamaCpp,
    healthSucceeds: true,
    inferenceSucceeds: true
  )
  let launcher = FakeProcessLauncher()
  let broker = RuntimeBroker(
    registry: try RuntimeAdapterRegistry(adapters: [adapter]),
    launcher: launcher,
    endpointCorrelator: FakeEndpointCorrelator(result: true)
  )
  let installation = runtimeInstallation()
  let identity = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity

  _ = try await broker.start(
    plan: executablePlan(installation: installation, identity: identity),
    installation: installation,
    verifyInference: true,
    timeout: .seconds(1),
    pollInterval: .milliseconds(1)
  )

  await broker.stopAllOwned(timeout: .seconds(1))

  #expect(await launcher.handle.wasTerminated())
  #expect(await broker.allInstances().allSatisfy { $0.state == .stopped })
}

@Test("A failed inference remains distinct from a healthy runtime")
func inferenceFailureDoesNotEraseHealthEvidence() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .llamaCpp,
    healthSucceeds: true,
    inferenceSucceeds: false
  )
  let launcher = FakeProcessLauncher()
  let broker = RuntimeBroker(
    registry: try RuntimeAdapterRegistry(adapters: [adapter]),
    launcher: launcher,
    endpointCorrelator: FakeEndpointCorrelator(result: true)
  )
  let installation = runtimeInstallation()
  let identity = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity

  let started = try await broker.start(
    plan: executablePlan(installation: installation, identity: identity),
    installation: installation,
    verifyInference: true,
    timeout: .seconds(1),
    pollInterval: .milliseconds(1)
  )
  #expect(started.instance.state == .running)
  #expect(started.instance.lastHealthCheck?.value == .runtimeReachable)
  #expect(started.instance.lastInferenceCheck?.value == .inferenceFailed)
  _ = try await broker.stop(started.instance.id, timeout: .seconds(1))
}

@Test("Provider-managed sessions cannot be stopped by process ownership inference")
func providerManagedStopIsBlocked() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .ollama,
    healthSucceeds: true,
    inferenceSucceeds: true
  )
  let broker = RuntimeBroker(
    registry: try RuntimeAdapterRegistry(adapters: [adapter]),
    launcher: FakeProcessLauncher()
  )
  let installation = runtimeInstallation()
  let endpoint = brokerURL(port: 11_434)
  let plan = RuntimeTestPlan(
    id: UUID(),
    adapterID: .ollama,
    installationID: installation.id,
    createdAt: .now,
    expiresAt: .now.addingTimeInterval(60),
    endpoint: endpoint,
    strategy: .providerManaged(endpoint: endpoint, externalIdentifier: "model"),
    stopBehavior: .providerStopUnavailable
  )

  let started = try await broker.start(
    plan: plan,
    installation: installation,
    verifyInference: false,
    timeout: .seconds(1),
    pollInterval: .milliseconds(1)
  )
  #expect(started.instance.lastHealthCheck?.value == .runtimeReachableUnauthenticated)
  await #expect(throws: RuntimeBrokerError.stopNotAllowed) {
    _ = try await broker.stop(started.instance.id)
  }
}

private func brokerURL(port: Int) -> URL {
  var components = URLComponents()
  components.scheme = "http"
  components.host = "127.0.0.1"
  components.port = port
  guard let url = components.url else { preconditionFailure("Valid test endpoint") }
  return url
}

@Test("Failed health check terminates only the newly launched process")
func failedHealthCheckCleansUpOwnedProcess() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .llamaCpp,
    healthSucceeds: false,
    inferenceSucceeds: false
  )
  let launcher = FakeProcessLauncher()
  let broker = RuntimeBroker(
    registry: try RuntimeAdapterRegistry(adapters: [adapter]),
    launcher: launcher,
    endpointCorrelator: FakeEndpointCorrelator(result: true)
  )
  let installation = runtimeInstallation()
  let identity = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity

  await #expect(throws: RuntimeBrokerError.self) {
    _ = try await broker.start(
      plan: executablePlan(installation: installation, identity: identity),
      installation: installation,
      verifyInference: false,
      timeout: .milliseconds(5),
      pollInterval: .milliseconds(1)
    )
  }
  #expect(await launcher.handle.wasTerminated())
  #expect(await broker.allInstances().isEmpty)
}

@Test("Cancellation terminates only the in-flight owned process")
func cancellationCleansUpOwnedProcess() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .llamaCpp,
    healthSucceeds: false,
    inferenceSucceeds: false
  )
  let launcher = FakeProcessLauncher()
  let broker = RuntimeBroker(
    registry: try RuntimeAdapterRegistry(adapters: [adapter]),
    launcher: launcher,
    endpointCorrelator: FakeEndpointCorrelator(result: true)
  )
  let installation = runtimeInstallation()
  let identity = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity
  let task = Task {
    try await broker.start(
      plan: executablePlan(installation: installation, identity: identity),
      installation: installation,
      verifyInference: false,
      timeout: .seconds(1),
      pollInterval: .milliseconds(50)
    )
  }
  try await Task.sleep(for: .milliseconds(5))
  task.cancel()

  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(await launcher.handle.wasTerminated())
  #expect(await broker.allInstances().isEmpty)
}

@Test("Stop timeout does not escalate to an unowned kill")
func stopTimeoutLeavesFailedOwnedSessionVisible() async throws {
  let adapter = FakeRuntimeAdapter(
    id: .llamaCpp,
    healthSucceeds: true,
    inferenceSucceeds: false
  )
  let launcher = FakeProcessLauncher(ignoresTermination: true)
  let broker = RuntimeBroker(
    registry: try RuntimeAdapterRegistry(adapters: [adapter]),
    launcher: launcher,
    endpointCorrelator: FakeEndpointCorrelator(result: true)
  )
  let installation = runtimeInstallation()
  let identity = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity
  let started = try await broker.start(
    plan: executablePlan(installation: installation, identity: identity),
    installation: installation,
    verifyInference: false,
    timeout: .seconds(1),
    pollInterval: .milliseconds(1)
  )

  await #expect(throws: RuntimeBrokerError.stopTimedOut) {
    _ = try await broker.stop(started.instance.id, timeout: .milliseconds(1))
  }
  let failed = try await broker.snapshot(for: started.instance.id)
  #expect(failed.instance.state == .failed)
}

@Test("Loopback port allocator detects a currently occupied preferred port")
func preferredPortConflictsAreReported() throws {
  let allocator = LoopbackPortAllocator()
  let candidate = try allocator.availablePort()
  let descriptor = socket(AF_INET, SOCK_STREAM, 0)
  #expect(descriptor >= 0)
  defer { close(descriptor) }
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = candidate.bigEndian
  address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
  let bindResult = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
      bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  #expect(bindResult == 0)

  #expect(throws: LoopbackPortAllocatorError.portUnavailable(candidate)) {
    _ = try allocator.availablePort(preferred: candidate)
  }
}
