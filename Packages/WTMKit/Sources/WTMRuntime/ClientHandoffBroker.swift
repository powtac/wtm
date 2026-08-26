import Foundation
import WTMDomain

public enum ClientHandoffBrokerError: Error, Equatable, Sendable {
  case expiredPlan
  case installationMismatch
  case invalidEndpoint
  case unsupportedStrategy
  case executableIdentityChanged
  case protectedResourceChanged
  case sessionNotFound
}

public struct ClientHandoffSnapshot: Sendable {
  public let id: UUID
  public let adapterID: ClientAdapterID
  public let installationID: ModelInstallation.ID
  public let processIdentifier: Int32
  public let isRunning: Bool
  public let exitStatus: Int32?
  public let logs: [RuntimeLogEntry]

  public init(
    id: UUID,
    adapterID: ClientAdapterID,
    installationID: ModelInstallation.ID,
    processIdentifier: Int32,
    isRunning: Bool,
    exitStatus: Int32?,
    logs: [RuntimeLogEntry]
  ) {
    self.id = id
    self.adapterID = adapterID
    self.installationID = installationID
    self.processIdentifier = processIdentifier
    self.isRunning = isRunning
    self.exitStatus = exitStatus
    self.logs = logs
  }
}

public actor ClientHandoffBroker {
  private struct Session: Sendable {
    let adapterID: ClientAdapterID
    let installationID: ModelInstallation.ID
    let processIdentifier: Int32
    let process: any RuntimeProcessHandle
    let logs: RuntimeLogBuffer
    var exitStatus: Int32?
  }

  private let launcher: any RuntimeProcessLaunching
  private let endpointPolicy: LoopbackEndpointPolicy
  private let inspector: ExecutableInspector
  private var sessions: [UUID: Session] = [:]

  public init(
    launcher: any RuntimeProcessLaunching = FoundationProcessLauncher(),
    endpointPolicy: LoopbackEndpointPolicy = LoopbackEndpointPolicy(),
    inspector: ExecutableInspector = ExecutableInspector()
  ) {
    self.launcher = launcher
    self.endpointPolicy = endpointPolicy
    self.inspector = inspector
  }

  public func start(
    plan: ClientHandoffPlan,
    installation: ModelInstallation
  ) async throws -> ClientHandoffSnapshot {
    guard plan.expiresAt > .now else { throw ClientHandoffBrokerError.expiredPlan }
    guard plan.installationID == installation.id else {
      throw ClientHandoffBrokerError.installationMismatch
    }
    do {
      try endpointPolicy.validate(plan.endpoint)
    } catch {
      throw ClientHandoffBrokerError.invalidEndpoint
    }
    guard case .executable(let handoff) = plan.strategy else {
      throw ClientHandoffBrokerError.unsupportedStrategy
    }
    let executable = try inspector.inspect(handoff.invocation.executableURL)
    guard executable.identity == handoff.invocation.approvedIdentity else {
      throw ClientHandoffBrokerError.executableIdentityChanged
    }
    for approvedIdentity in handoff.protectedResourceIdentities {
      let current = try inspector.inspect(approvedIdentity.requestedURL)
      guard current.identity == approvedIdentity else {
        throw ClientHandoffBrokerError.protectedResourceChanged
      }
    }

    let logs = RuntimeLogBuffer(
      maximumEntries: 100,
      maximumUTF8ByteCount: 32_768,
      redactor: RuntimeLogRedactor(
        sensitiveValues: [installation.rootURL.path]
      )
    )
    let securedInvocation = RuntimeExecutableInvocation(
      executableURL: handoff.invocation.executableURL,
      arguments: handoff.invocation.arguments,
      currentDirectoryURL: handoff.invocation.currentDirectoryURL,
      environment: handoff.invocation.environment,
      approvedIdentity: handoff.invocation.approvedIdentity,
      protectedResourceIdentities: handoff.protectedResourceIdentities
    )
    let process = try launcher.launch(securedInvocation) { stream, text in
      logs.append(text, stream: stream)
    }
    let sessionID = UUID()
    let processIdentifier = await process.processIdentifier()
    sessions[sessionID] = Session(
      adapterID: plan.adapterID,
      installationID: installation.id,
      processIdentifier: processIdentifier,
      process: process,
      logs: logs,
      exitStatus: nil
    )
    Task { [weak self, process] in
      let status = await process.waitForExit()
      await self?.recordExit(status, sessionID: sessionID)
    }
    return makeSnapshot(sessionID: sessionID)
  }

  public func snapshot(sessionID: UUID) throws -> ClientHandoffSnapshot {
    guard sessions[sessionID] != nil else { throw ClientHandoffBrokerError.sessionNotFound }
    return makeSnapshot(sessionID: sessionID)
  }

  public func stopAllOwned() async {
    let activeProcesses = sessions.values.compactMap { session in
      session.exitStatus == nil ? session.process : nil
    }
    for process in activeProcesses {
      await process.terminate()
    }
  }

  private func recordExit(_ status: Int32, sessionID: UUID) {
    guard var session = sessions[sessionID] else { return }
    session.exitStatus = status
    sessions[sessionID] = session
  }

  private func makeSnapshot(sessionID: UUID) -> ClientHandoffSnapshot {
    guard let session = sessions[sessionID] else {
      preconditionFailure("Snapshot is requested only for a registered handoff")
    }
    return ClientHandoffSnapshot(
      id: sessionID,
      adapterID: session.adapterID,
      installationID: session.installationID,
      processIdentifier: session.processIdentifier,
      isRunning: session.exitStatus == nil,
      exitStatus: session.exitStatus,
      logs: session.logs.snapshot()
    )
  }
}
