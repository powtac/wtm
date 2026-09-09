import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

public struct LocalAIRuntimeAdapter: RuntimeAdapter {
  public let id = RuntimeAdapterID.localAI
  public let displayName = "LocalAI"
  public let version = "1"
  public let supportedFormats: Set<ModelFormat> = [.gguf]
  private let connection: @Sendable (String) -> LocalModelConnection?
  private let transport: @Sendable (URL) throws -> any LocalAIRuntimeTransport

  public init(
    connection: @escaping @Sendable (String) -> LocalModelConnection?,
    transport: @escaping @Sendable (URL) throws -> any LocalAIRuntimeTransport = {
      try LocalAIHTTPTransport(endpoint: $0)
    }
  ) {
    self.connection = connection
    self.transport = transport
  }

  public func readiness(for installation: ModelInstallation, environment: RuntimeEnvironment) async
    -> RuntimeReadiness
  {
    let integrity: ModelIntegrity =
      installation.artifacts.contains(where: \.isPartial)
      ? .partial : (installation.state == .stored ? .complete : .unknown)
    var compatibility = RuntimeCompatibility.compatible
    var validation = ModelValidation.blocked
    var blockers: [String] = []
    do {
      guard ["arm64", "arm64e"].contains(environment.architecture) else {
        throw RuntimeAdapterError.invalidToolDefinition
      }
      let config = try configuration(installation)
      let api = try transport(config.endpoint)
      try await api.health()
      guard try await api.models().contains(config.modelReference) else {
        throw RuntimeAdapterError.endpointUnavailable
      }
      validation = .runtimeReachableUnauthenticated
    } catch {
      compatibility = .runtimeUnavailable
      blockers = [
        "Configure the exact local endpoint and model ID, then start LocalAI separately. API reachability does not prove provider or file identity."
      ]
    }
    return RuntimeReadiness(
      installationID: installation.id, adapterID: id,
      integrity: observation(integrity),
      compatibility: observation(compatibility), validation: observation(validation),
      runtime: observation(RuntimeState.stopped), blockers: blockers)
  }

  public func makeTestPlan(for installation: ModelInstallation, context: RuntimeLaunchContext)
    async throws -> RuntimeTestPlan
  {
    let config = try configuration(installation)
    return RuntimeTestPlan(
      id: UUID(), adapterID: id, installationID: installation.id,
      createdAt: context.now, expiresAt: context.now.addingTimeInterval(120),
      endpoint: config.endpoint,
      strategy: .providerManaged(
        endpoint: config.endpoint, externalIdentifier: config.modelReference),
      stopBehavior: .providerStopUnavailable)
  }

  public func healthCheck(endpoint: URL) async -> RuntimeProbeResult {
    do {
      try await transport(endpoint).health()
      return RuntimeProbeResult(
        succeeded: true, checkedAt: .now,
        summary: "Configured local API is reachable; provider identity is unverified.")
    } catch {
      return RuntimeProbeResult(
        succeeded: false, checkedAt: .now, summary: "LocalAI health check failed.")
    }
  }

  public func inferenceCheck(endpoint: URL, installation: ModelInstallation, prompt: String) async
    -> RuntimeProbeResult
  {
    guard let plan = try? await makeTestPlan(for: installation, context: RuntimeLaunchContext()),
      plan.endpoint == endpoint
    else {
      return RuntimeProbeResult(
        succeeded: false, checkedAt: .now, summary: "LocalAI mapping is unavailable.")
    }
    return await inferenceCheck(plan: plan, installation: installation, prompt: prompt)
  }

  public func inferenceCheck(plan: RuntimeTestPlan, installation: ModelInstallation, prompt: String)
    async -> RuntimeProbeResult
  {
    do {
      let config = try configuration(installation)
      guard plan.expiresAt > .now, plan.installationID == installation.id, plan.adapterID == id,
        case .providerManaged(let endpoint, let approvedReference) = plan.strategy,
        endpoint == plan.endpoint, config.endpoint == endpoint,
        approvedReference == config.modelReference
      else { throw RuntimeAdapterError.endpointUnavailable }
      let api = try transport(plan.endpoint)
      let reference = config.modelReference
      guard try await api.models().contains(reference) else {
        throw RuntimeAdapterError.endpointUnavailable
      }
      let response = try await api.generate(model: reference, prompt: prompt)
      return RuntimeProbeResult(
        succeeded: true, checkedAt: .now,
        summary:
          "Configured LocalAI model completed one-token inference; local file mapping is user-supplied.",
        responseExcerpt: response)
    } catch {
      return RuntimeProbeResult(
        succeeded: false, checkedAt: .now, summary: "LocalAI model verification failed.")
    }
  }

  private func configuration(_ installation: ModelInstallation) throws -> LocalModelConnection {
    guard supportedFormats.contains(installation.variant.format), installation.state == .stored,
      !installation.artifacts.contains(where: \.isPartial), let config = connection(installation.id)
    else { throw RuntimeAdapterError.invalidToolDefinition }
    try LocalModelConnectionPolicy().validate(config)
    return config
  }

  private func observation<T: Hashable & Codable & Sendable>(_ value: T) -> RuntimeObservation<T> {
    RuntimeObservation(
      value: value, adapterID: id, adapterVersion: version,
      checkedAt: .now, expiresAt: Date.now.addingTimeInterval(15),
      evidence: "Explicit user mapping and unauthenticated numeric-loopback API")
  }
}
