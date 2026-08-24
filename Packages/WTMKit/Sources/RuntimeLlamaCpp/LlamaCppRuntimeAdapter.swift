import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

public struct LlamaCppRuntimeAdapter: RuntimeAdapter {
  public let id = RuntimeAdapterID.llamaCpp
  public let displayName = "llama.cpp"
  public let version = "1"
  public let supportedFormats: Set<ModelFormat> = [.gguf]

  private let configuredDefinition: ToolDefinition?
  private let configuredApproval: ToolExecutionApproval?
  private let invocationBuilder: ToolInvocationBuilder
  private let portAllocator: LoopbackPortAllocator
  private let transport: any LlamaCppRuntimeTransport

  public init(
    configuredDefinition: ToolDefinition? = nil,
    configuredApproval: ToolExecutionApproval? = nil,
    invocationBuilder: ToolInvocationBuilder = ToolInvocationBuilder(),
    portAllocator: LoopbackPortAllocator = LoopbackPortAllocator(),
    transport: any LlamaCppRuntimeTransport = LlamaCppHTTPRuntimeTransport()
  ) {
    self.configuredDefinition = configuredDefinition
    self.configuredApproval = configuredApproval
    self.invocationBuilder = invocationBuilder
    self.portAllocator = portAllocator
    self.transport = transport
  }

  public func readiness(
    for installation: ModelInstallation,
    environment: RuntimeEnvironment
  ) async -> RuntimeReadiness {
    let checkedAt = Date.now
    let integrityValue = integrity(for: installation)
    let estimate = memoryEstimate(for: installation)
    var compatibilityValue: RuntimeCompatibility
    var validationValue: ModelValidation
    var blockers: [String] = []

    if !supportedFormats.contains(installation.variant.format) {
      compatibilityValue = .unsupportedFormat
      validationValue = .blocked
      blockers.append("llama.cpp requires a GGUF model.")
    } else if let definition = environment.toolDefinition ?? configuredDefinition {
      do {
        _ = try invocationBuilder.inspect(definition, checkedAt: checkedAt)
        compatibilityValue = .compatible
        validationValue = .staticCompatible
        if !definition.isEnabled || (environment.toolApproval ?? configuredApproval) == nil {
          blockers.append("Enable and approve the discovered llama.cpp executable before launch.")
        }
      } catch {
        compatibilityValue = .runtimeNotInstalled
        validationValue = .blocked
        blockers.append("The configured llama.cpp executable failed static validation.")
      }
    } else {
      compatibilityValue = .runtimeNotInstalled
      validationValue = .blocked
      blockers.append("No llama.cpp executable is configured.")
    }

    if let capacity = environment.memoryCapacityByteCount,
      estimate.byteCount > capacity,
      compatibilityValue == .compatible
    {
      compatibilityValue = .insufficientMemory
      blockers.append("Estimated model memory exceeds installed unified-memory capacity.")
    }

    return RuntimeReadiness(
      installationID: installation.id,
      adapterID: id,
      integrity: observation(integrityValue, at: checkedAt, evidence: "Inventory state"),
      compatibility: observation(
        compatibilityValue,
        at: checkedAt,
        evidence: "GGUF format, executable identity, architecture, and memory estimate"
      ),
      validation: observation(
        validationValue,
        at: checkedAt,
        evidence: "Static validation only; no process or model request"
      ),
      runtime: observation(
        RuntimeState.stopped,
        at: checkedAt,
        expiresAt: checkedAt.addingTimeInterval(15),
        evidence: "No WTM-owned llama.cpp session"
      ),
      estimatedMemory: estimate,
      blockers: blockers
    )
  }

  public func makeTestPlan(
    for installation: ModelInstallation,
    context: RuntimeLaunchContext
  ) async throws -> RuntimeTestPlan {
    guard supportedFormats.contains(installation.variant.format) else {
      throw RuntimeAdapterError.unsupportedFormat(installation.variant.format)
    }
    guard let definition = context.toolDefinition ?? configuredDefinition else {
      throw RuntimeAdapterError.runtimeNotInstalled
    }
    guard let approval = context.toolApproval ?? configuredApproval else {
      throw RuntimeAdapterError.executableNotApproved
    }
    guard let modelURL = modelURL(for: installation) else {
      throw RuntimeAdapterError.invalidToolDefinition
    }
    let port = try context.port ?? portAllocator.availablePort()
    let endpoint = try endpoint(port: port)
    let invocation = try invocationBuilder.makeInvocation(
      definition: definition,
      values: RuntimeArgumentValues(
        modelPath: modelURL.path,
        modelID: installation.identity.id,
        endpoint: endpoint.absoluteString,
        port: port,
        configPath: installation.configurationURLs.first?.path
      ),
      modelFormat: installation.variant.format,
      approval: approval
    )
    guard hasSingleArgument(invocation.arguments, name: "--host", value: "127.0.0.1"),
      hasSingleArgument(invocation.arguments, name: "--port", value: String(port)),
      hasSingleArgument(invocation.arguments, name: "--model", value: modelURL.path)
    else {
      throw RuntimeAdapterError.invalidToolDefinition
    }
    return RuntimeTestPlan(
      id: UUID(),
      adapterID: id,
      installationID: installation.id,
      createdAt: context.now,
      expiresAt: context.now.addingTimeInterval(120),
      endpoint: endpoint,
      strategy: .executable(invocation),
      stopBehavior: .stopOwnedProcess,
      estimatedMemory: memoryEstimate(for: installation)
    )
  }

  public func healthCheck(endpoint: URL) async -> RuntimeProbeResult {
    do {
      let healthy = try await transport.isHealthy(endpoint: endpoint)
      return RuntimeProbeResult(
        succeeded: healthy,
        checkedAt: .now,
        summary: healthy ? "llama.cpp health check passed" : "llama.cpp is still loading"
      )
    } catch {
      return RuntimeProbeResult(
        succeeded: false,
        checkedAt: .now,
        summary: "llama.cpp health check failed"
      )
    }
  }

  public func inferenceCheck(
    endpoint: URL,
    installation: ModelInstallation,
    prompt: String
  ) async -> RuntimeProbeResult {
    do {
      let response = try await transport.complete(endpoint: endpoint, prompt: prompt)
      return RuntimeProbeResult(
        succeeded: true,
        checkedAt: .now,
        summary: "llama.cpp completed a one-token inference request",
        responseExcerpt: String(response.prefix(200))
      )
    } catch {
      return RuntimeProbeResult(
        succeeded: false,
        checkedAt: .now,
        summary: "llama.cpp inference request failed"
      )
    }
  }

  private func modelURL(for installation: ModelInstallation) -> URL? {
    let candidates = installation.artifacts.filter {
      $0.kind == .weights && $0.url.pathExtension.lowercased() == "gguf" && !$0.isPartial
    }.map(\.url)
    if candidates.count == 1 { return candidates[0] }
    if installation.rootURL.pathExtension.lowercased() == "gguf" { return installation.rootURL }
    return nil
  }

  private func endpoint(port: UInt16) throws -> URL {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = Int(port)
    guard let url = components.url else { throw RuntimeAdapterError.endpointUnavailable }
    return url
  }

  private func hasSingleArgument(_ arguments: [String], name: String, value: String) -> Bool {
    let indices = arguments.indices.filter { arguments[$0] == name }
    guard indices.count == 1, let index = indices.first, arguments.indices.contains(index + 1)
    else { return false }
    guard arguments[index + 1] == value else { return false }
    return !arguments.contains { $0.hasPrefix(name + "=") }
  }

  private func integrity(for installation: ModelInstallation) -> ModelIntegrity {
    switch installation.state {
    case .stored: installation.artifacts.contains(where: \Artifact.isPartial) ? .partial : .complete
    case .incomplete: .partial
    case .issue: .corrupt
    case .offline: .unknown
    }
  }

  private func memoryEstimate(for installation: ModelInstallation) -> RuntimeMemoryEstimate {
    let weights = installation.artifacts.filter { $0.kind == .weights }.reduce(Int64(0)) {
      $0 + $1.logicalByteCount
    }
    return RuntimeMemoryEstimate(
      byteCount: weights + max(weights / 5, 512 * 1_024 * 1_024),
      basis: "GGUF weights plus 20% or 512 MB runtime overhead; estimate only"
    )
  }

  private func observation<Value: Hashable & Codable & Sendable>(
    _ value: Value,
    at checkedAt: Date,
    expiresAt: Date? = nil,
    evidence: String
  ) -> RuntimeObservation<Value> {
    RuntimeObservation(
      value: value,
      adapterID: id,
      adapterVersion: version,
      checkedAt: checkedAt,
      expiresAt: expiresAt,
      evidence: evidence
    )
  }
}
