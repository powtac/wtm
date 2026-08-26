import ClientOpenClaw
import ClientUnsloth
import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

private var testHomePath: String {
  ProcessInfo.processInfo.environment["WTM_TEST_HOME_PATH"] ?? "/tmp/wtm-test-home"
}

private func installation(
  providerID: ProviderID = .ollama,
  format: ModelFormat = .ollama
) -> ModelInstallation {
  ModelInstallation(
    id: "installation",
    identity: ModelIdentity(id: "model", displayName: "gpt-oss"),
    variant: ModelVariant(
      id: format == .ollama ? "ollama:gpt-oss:20b" : "model:variant",
      identityID: "model",
      format: format
    ),
    sourceID: "source",
    providerID: providerID,
    rootURL: URL(filePath: "/models/gpt-oss", directoryHint: .isDirectory),
    state: .stored,
    artifacts: []
  )
}

private func verifiedOllamaRuntime(
  at now: Date,
  ownership: RuntimeOwnership = .startedByWTM
) -> RuntimeInstance {
  guard let endpoint = URL(string: "http://127.0.0.1:11434") else {
    preconditionFailure("Static loopback URL must be valid")
  }
  let verified = RuntimeObservation(
    value: ModelValidation.inferenceVerified,
    adapterID: RuntimeAdapterID.ollama,
    adapterVersion: "1",
    checkedAt: now,
    expiresAt: now.addingTimeInterval(60),
    evidence: "test"
  )
  return RuntimeInstance(
    id: UUID(),
    adapterID: .ollama,
    installationID: "installation",
    endpoint: endpoint,
    state: .running,
    ownership: ownership,
    lastInferenceCheck: verified
  )
}

private actor ExitingProcessHandle: RuntimeProcessHandle {
  func processIdentifier() async -> Int32 { 42 }

  func isRunning() async -> Bool { false }

  func terminate() async {}

  func waitForExit() async -> Int32 { 0 }
}

private struct ExitingProcessLauncher: RuntimeProcessLaunching, Sendable {
  let handle = ExitingProcessHandle()

  func launch(
    _ invocation: RuntimeExecutableInvocation,
    outputHandler: @escaping RuntimeProcessOutputHandler
  ) throws -> any RuntimeProcessHandle {
    handle
  }
}

@Test("Client registry rejects duplicate capability IDs")
func registryRejectsDuplicates() {
  let first = OpenClawClientAdapter(nodeURL: nil, scriptURL: nil, environment: [:])
  let second = OpenClawClientAdapter(nodeURL: nil, scriptURL: nil, environment: [:])
  #expect(throws: ClientAdapterRegistryError.duplicateClient(.openClaw)) {
    try ClientAdapterRegistry(adapters: [first, second])
  }
}

@Test("OpenClaw handoff requires fresh Ollama inference evidence")
func openClawRequiresVerifiedRuntime() throws {
  let adapter = OpenClawClientAdapter(
    nodeURL: URL(filePath: "/usr/bin/true"),
    scriptURL: URL(filePath: "/usr/bin/true"),
    environment: [:]
  )
  let model = installation()
  #expect(throws: ClientAdapterError.verifiedRuntimeRequired) {
    try adapter.makeHandoffPlan(for: model, context: ClientHandoffContext())
  }
}

@Test("OpenClaw rejects provider-managed Ollama evidence as unauthenticated")
func openClawRejectsProviderManagedEvidence() throws {
  let now = Date(timeIntervalSince1970: 100)
  let adapter = OpenClawClientAdapter(
    nodeURL: URL(filePath: "/usr/bin/true"),
    scriptURL: URL(filePath: "/usr/bin/true"),
    environment: [:]
  )
  #expect(throws: ClientAdapterError.verifiedRuntimeRequired) {
    try adapter.makeHandoffPlan(
      for: installation(),
      context: ClientHandoffContext(
        now: now,
        runtimeInstances: [verifiedOllamaRuntime(at: now, ownership: .providerManaged)]
      )
    )
  }
}

@Test("OpenClaw uses a provider-qualified reference and typed argument vector")
func openClawBuildsReviewedPlan() throws {
  let now = Date(timeIntervalSince1970: 100)
  let adapter = OpenClawClientAdapter(
    nodeURL: URL(filePath: "/usr/bin/true"),
    scriptURL: URL(filePath: "/usr/bin/true"),
    environment: ["HOME": testHomePath]
  )
  let plan = try adapter.makeHandoffPlan(
    for: installation(),
    context: ClientHandoffContext(
      now: now,
      runtimeInstances: [verifiedOllamaRuntime(at: now)]
    )
  )
  #expect(plan.modelReference == "ollama/gpt-oss:20b")
  guard case .executable(let handoff) = plan.strategy else {
    Issue.record("Expected executable handoff")
    return
  }
  #expect(handoff.invocation.arguments.contains("ollama/gpt-oss:20b"))
  #expect(handoff.invocation.arguments.contains("Reply with exactly: pong"))
  #expect(handoff.protectedResourceIdentities.count == 1)
}

@Test("Unsloth plan disables public tunnel and tools")
func unslothBuildsRestrictedStudioPlan() throws {
  let adapter = UnslothClientAdapter(
    pythonURL: URL(filePath: "/usr/bin/true"),
    scriptURL: URL(filePath: "/usr/bin/true"),
    environment: [:]
  )
  let plan = try adapter.makeHandoffPlan(
    for: installation(providerID: .manual, format: .gguf),
    context: ClientHandoffContext(now: Date(timeIntervalSince1970: 100))
  )
  guard case .executable(let handoff) = plan.strategy else {
    Issue.record("Expected executable handoff")
    return
  }
  #expect(handoff.invocation.arguments.contains("--api-only"))
  #expect(handoff.invocation.arguments.contains("--no-cloudflare"))
  #expect(handoff.invocation.arguments.contains("--disable-tools"))
  #expect(!handoff.invocation.arguments.contains("train"))
  #expect(plan.endpoint.absoluteString == "http://127.0.0.1:8888")
}

@Test("Client broker revalidates and owns the reviewed process")
func clientBrokerStartsReviewedPlan() async throws {
  let model = installation(providerID: .manual, format: .gguf)
  let executable = try ExecutableInspector().inspect(URL(filePath: "/usr/bin/true")).identity
  let now = Date.now
  guard let endpoint = URL(string: "http://127.0.0.1:8888") else {
    preconditionFailure("Static loopback URL must be valid")
  }
  let invocation = RuntimeExecutableInvocation(
    executableURL: executable.canonicalURL,
    arguments: [],
    approvedIdentity: executable
  )
  let plan = ClientHandoffPlan(
    adapterID: .unsloth,
    installationID: model.id,
    modelReference: model.rootURL.path,
    createdAt: now,
    expiresAt: now.addingTimeInterval(60),
    endpoint: endpoint,
    strategy: .executable(
      ClientExecutableHandoff(
        invocation: invocation,
        protectedResourceIdentities: [executable]
      )
    )
  )
  let broker = ClientHandoffBroker(launcher: ExitingProcessLauncher())
  let started = try await broker.start(plan: plan, installation: model)
  #expect(started.processIdentifier > 0)
  var finished = try await broker.snapshot(sessionID: started.id)
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while finished.exitStatus == nil && ContinuousClock.now < deadline {
    do {
      try await Task.sleep(for: .milliseconds(10))
    } catch is CancellationError {
      return
    }
    finished = try await broker.snapshot(sessionID: started.id)
  }
  #expect(finished.exitStatus == 0)
}
