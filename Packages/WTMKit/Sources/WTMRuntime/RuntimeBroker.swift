import Foundation
import WTMAdapterContracts
import WTMDomain

public enum RuntimeBrokerError: Error, Equatable, Sendable {
  case expiredPlan
  case adapterUnavailable(RuntimeAdapterID)
  case installationMismatch
  case invalidEndpoint
  case executableIdentityChanged
  case endpointOwnershipMismatch
  case processExited(Int32)
  case healthCheckTimedOut
  case healthCheckFailed(String)
  case sessionNotFound
  case stopNotAllowed
  case stopTimedOut
}

public struct RuntimeSessionSnapshot: Sendable {
  public let instance: RuntimeInstance
  public let health: RuntimeProbeResult?
  public let inference: RuntimeProbeResult?
  public let logs: [RuntimeLogEntry]

  public init(
    instance: RuntimeInstance,
    health: RuntimeProbeResult?,
    inference: RuntimeProbeResult?,
    logs: [RuntimeLogEntry]
  ) {
    self.instance = instance
    self.health = health
    self.inference = inference
    self.logs = logs
  }
}

public actor RuntimeBroker {
  private struct Session: Sendable {
    var instance: RuntimeInstance
    let process: (any RuntimeProcessHandle)?
    let adapter: any RuntimeAdapter
    let installation: ModelInstallation
    let logs: RuntimeLogBuffer
    var health: RuntimeProbeResult?
    var inference: RuntimeProbeResult?
  }

  private let registry: RuntimeAdapterRegistry
  private let launcher: any RuntimeProcessLaunching
  private let endpointPolicy: LoopbackEndpointPolicy
  private let inspector: ExecutableInspector
  private let endpointCorrelator: any RuntimeEndpointCorrelating
  private var sessions: [RuntimeInstance.ID: Session] = [:]

  public init(
    registry: RuntimeAdapterRegistry,
    launcher: any RuntimeProcessLaunching = FoundationProcessLauncher(),
    endpointPolicy: LoopbackEndpointPolicy = LoopbackEndpointPolicy(),
    inspector: ExecutableInspector = ExecutableInspector(),
    endpointCorrelator: any RuntimeEndpointCorrelating = DarwinProcessEndpointCorrelator()
  ) {
    self.registry = registry
    self.launcher = launcher
    self.endpointPolicy = endpointPolicy
    self.inspector = inspector
    self.endpointCorrelator = endpointCorrelator
  }

  public func start(
    plan: RuntimeTestPlan,
    installation: ModelInstallation,
    verifyInference: Bool,
    prompt: String = "Reply with OK.",
    timeout: Duration = .seconds(60),
    pollInterval: Duration = .milliseconds(300)
  ) async throws -> RuntimeSessionSnapshot {
    guard plan.expiresAt > .now else { throw RuntimeBrokerError.expiredPlan }
    guard installation.id == plan.installationID else {
      throw RuntimeBrokerError.installationMismatch
    }
    guard let adapter = registry.adapter(for: plan.adapterID) else {
      throw RuntimeBrokerError.adapterUnavailable(plan.adapterID)
    }
    do {
      try endpointPolicy.validate(plan.endpoint)
    } catch {
      throw RuntimeBrokerError.invalidEndpoint
    }

    let id = UUID()
    let logs = RuntimeLogBuffer(
      redactor: RuntimeLogRedactor(sensitiveValues: Array(planSensitiveValues(plan)))
    )
    let process: (any RuntimeProcessHandle)?
    let ownership: RuntimeOwnership
    let externalIdentifier: String?
    switch plan.strategy {
    case .providerManaged(let endpoint, let identifier):
      guard endpoint == plan.endpoint else { throw RuntimeBrokerError.invalidEndpoint }
      process = nil
      ownership = .providerManaged
      externalIdentifier = identifier
    case .executable(let invocation):
      let inspection = try inspector.inspect(invocation.executableURL)
      guard inspection.identity == invocation.approvedIdentity else {
        throw RuntimeBrokerError.executableIdentityChanged
      }
      process = try launcher.launch(invocation) { stream, text in
        logs.append(text, stream: stream)
      }
      ownership = .startedByWTM
      if let process {
        externalIdentifier = String(await process.processIdentifier())
      } else {
        externalIdentifier = nil
      }
    }

    let startingInstance = RuntimeInstance(
      id: id,
      adapterID: plan.adapterID,
      installationID: installation.id,
      externalIdentifier: externalIdentifier,
      endpoint: plan.endpoint,
      state: .starting,
      startedAt: .now,
      ownership: ownership
    )
    sessions[id] = Session(
      instance: startingInstance,
      process: process,
      adapter: adapter,
      installation: installation,
      logs: logs,
      health: nil,
      inference: nil
    )

    do {
      let health = try await waitUntilHealthy(
        sessionID: id,
        timeout: timeout,
        pollInterval: pollInterval
      )
      try await validateOwnedRuntimeEndpoint(sessionID: id)
      var inference: RuntimeProbeResult?
      if verifyInference {
        inference = await adapter.inferenceCheck(
          endpoint: plan.endpoint,
          installation: installation,
          prompt: prompt
        )
        try await validateOwnedRuntimeEndpoint(sessionID: id)
      }
      let validationValue: ModelValidation
      if let inference {
        validationValue =
          inference.succeeded
          ? (ownership == .startedByWTM ? .inferenceVerified : .runtimeReachableUnauthenticated)
          : .inferenceFailed
      } else {
        validationValue =
          ownership == .startedByWTM
          ? .runtimeReachable : .runtimeReachableUnauthenticated
      }
      let checkedAt = inference?.checkedAt ?? health.checkedAt
      let runningInstance = RuntimeInstance(
        id: id,
        adapterID: plan.adapterID,
        installationID: installation.id,
        externalIdentifier: externalIdentifier,
        endpoint: plan.endpoint,
        state: .running,
        startedAt: startingInstance.startedAt,
        ownership: ownership,
        lastHealthCheck: RuntimeObservation(
          value: ownership == .startedByWTM
            ? .runtimeReachable : .runtimeReachableUnauthenticated,
          adapterID: adapter.id,
          adapterVersion: adapter.version,
          checkedAt: health.checkedAt,
          expiresAt: health.checkedAt.addingTimeInterval(30),
          evidence: health.summary
        ),
        lastInferenceCheck: inference.map {
          RuntimeObservation(
            value: validationValue,
            adapterID: adapter.id,
            adapterVersion: adapter.version,
            checkedAt: checkedAt,
            evidence: $0.summary
          )
        }
      )
      guard var session = sessions[id] else { throw RuntimeBrokerError.sessionNotFound }
      session.instance = runningInstance
      session.health = health
      session.inference = inference
      sessions[id] = session
      return RuntimeSessionSnapshot(
        instance: runningInstance,
        health: health,
        inference: inference,
        logs: logs.snapshot()
      )
    } catch {
      await stopOwnedProcessIfPresent(sessionID: id)
      sessions.removeValue(forKey: id)
      throw error
    }
  }

  public func snapshot(for id: RuntimeInstance.ID) async throws -> RuntimeSessionSnapshot {
    guard let session = sessions[id] else { throw RuntimeBrokerError.sessionNotFound }
    return RuntimeSessionSnapshot(
      instance: session.instance,
      health: session.health,
      inference: session.inference,
      logs: session.logs.snapshot()
    )
  }

  public func allInstances() -> [RuntimeInstance] {
    sessions.values.map(\.instance).sorted { $0.id.uuidString < $1.id.uuidString }
  }

  public func stop(
    _ id: RuntimeInstance.ID,
    timeout: Duration = .seconds(10)
  ) async throws -> RuntimeSessionSnapshot {
    guard var session = sessions[id] else { throw RuntimeBrokerError.sessionNotFound }
    guard session.instance.ownership == .startedByWTM, let process = session.process else {
      throw RuntimeBrokerError.stopNotAllowed
    }
    session.instance = replacingState(of: session.instance, with: .stopping)
    sessions[id] = session
    await process.terminate()

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while await process.isRunning(), clock.now < deadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    guard await !process.isRunning() else {
      session.instance = replacingState(of: session.instance, with: .failed)
      sessions[id] = session
      throw RuntimeBrokerError.stopTimedOut
    }
    _ = await process.waitForExit()
    session.instance = replacingState(of: session.instance, with: .stopped)
    sessions[id] = session
    return RuntimeSessionSnapshot(
      instance: session.instance,
      health: session.health,
      inference: session.inference,
      logs: session.logs.snapshot()
    )
  }

  /// Stops every live process handle created by this broker.
  /// Provider-managed runtimes are deliberately excluded.
  public func stopAllOwned(timeout: Duration = .seconds(10)) async {
    let ownedIDs = sessions.values
      .filter { $0.instance.ownership == .startedByWTM && $0.instance.state != .stopped }
      .map(\.instance.id)
    for id in ownedIDs {
      _ = try? await stop(id, timeout: timeout)
    }
  }

  private func waitUntilHealthy(
    sessionID: RuntimeInstance.ID,
    timeout: Duration,
    pollInterval: Duration
  ) async throws -> RuntimeProbeResult {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var lastFailure = "Runtime did not answer."
    while clock.now < deadline {
      try Task.checkCancellation()
      guard let session = sessions[sessionID] else {
        throw RuntimeBrokerError.sessionNotFound
      }
      if let process = session.process, await !process.isRunning() {
        throw RuntimeBrokerError.processExited(await process.waitForExit())
      }
      let result = await session.adapter.healthCheck(endpoint: session.instance.endpoint)
      if result.succeeded { return result }
      lastFailure = result.summary
      try await Task.sleep(for: pollInterval)
    }
    if lastFailure.isEmpty {
      throw RuntimeBrokerError.healthCheckTimedOut
    }
    throw RuntimeBrokerError.healthCheckFailed(lastFailure)
  }

  private func stopOwnedProcessIfPresent(sessionID: RuntimeInstance.ID) async {
    guard let session = sessions[sessionID], session.instance.ownership == .startedByWTM,
      let process = session.process
    else { return }
    await process.terminate()
  }

  private func validateOwnedRuntimeEndpoint(sessionID: RuntimeInstance.ID) async throws {
    guard let session = sessions[sessionID], let process = session.process else { return }
    guard await process.isRunning() else {
      throw RuntimeBrokerError.processExited(await process.waitForExit())
    }
    let processIdentifier = await process.processIdentifier()
    guard
      await endpointCorrelator.ownsListener(
        processIdentifier: processIdentifier,
        endpoint: session.instance.endpoint
      )
    else { throw RuntimeBrokerError.endpointOwnershipMismatch }
    guard await process.isRunning() else {
      throw RuntimeBrokerError.processExited(await process.waitForExit())
    }
  }

  private func replacingState(of instance: RuntimeInstance, with state: RuntimeState)
    -> RuntimeInstance
  {
    RuntimeInstance(
      id: instance.id,
      adapterID: instance.adapterID,
      installationID: instance.installationID,
      externalIdentifier: instance.externalIdentifier,
      endpoint: instance.endpoint,
      state: state,
      startedAt: instance.startedAt,
      ownership: instance.ownership,
      lastHealthCheck: instance.lastHealthCheck,
      lastInferenceCheck: instance.lastInferenceCheck
    )
  }

  private func planSensitiveValues(_ plan: RuntimeTestPlan) -> Set<String> {
    guard case .executable(let invocation) = plan.strategy else { return [] }
    return Set(invocation.environment.values)
  }
}
