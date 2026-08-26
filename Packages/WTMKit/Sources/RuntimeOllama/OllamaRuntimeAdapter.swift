import Foundation
import WTMAdapterContracts
import WTMDomain

public struct OllamaRuntimeAdapter: RuntimeAdapter {
  public let id = RuntimeAdapterID.ollama
  public let displayName = "Ollama"
  public let version = "1"
  public let supportedFormats: Set<ModelFormat> = [.ollama]

  private let endpoint: URL
  private let transport: any OllamaRuntimeTransport

  public init(endpoint: URL, transport: any OllamaRuntimeTransport) {
    self.endpoint = endpoint
    self.transport = transport
  }

  public init(endpoint: URL) throws {
    self.endpoint = endpoint
    transport = try OllamaHTTPRuntimeTransport(baseURL: endpoint)
  }

  public func readiness(
    for installation: ModelInstallation,
    environment: RuntimeEnvironment
  ) async -> RuntimeReadiness {
    let checkedAt = Date.now
    let integrityValue = integrity(for: installation)
    var compatibilityValue: RuntimeCompatibility
    var validationValue: ModelValidation
    var runtimeValue = RuntimeState.stopped
    var blockers: [String] = []

    if !supportedFormats.contains(installation.variant.format) {
      compatibilityValue = .unsupportedFormat
      validationValue = .blocked
      blockers.append("Ollama runs only Ollama-managed model installations.")
    } else if !supportsArchitecture(environment.architecture) {
      compatibilityValue = .unsupportedArchitecture
      validationValue = .blocked
      blockers.append("Ollama requires Apple Silicon in this WTM release.")
    } else {
      compatibilityValue = .compatible
      validationValue = .staticCompatible
      do {
        _ = try await transport.availableModelNames()
        let runningNames = try await transport.runningModelNames()
        if let modelName = modelName(for: installation), contains(modelName, in: runningNames) {
          runtimeValue = .running
          validationValue = .runtimeReachableUnauthenticated
        }
      } catch {
        compatibilityValue = .runtimeUnavailable
        validationValue = .blocked
        blockers.append("Ollama's local API is not reachable.")
      }
    }

    return RuntimeReadiness(
      installationID: installation.id,
      adapterID: id,
      integrity: observation(integrityValue, at: checkedAt, evidence: "Inventory state"),
      compatibility: observation(
        compatibilityValue,
        at: checkedAt,
        evidence: "Ollama format and loopback API"
      ),
      validation: observation(
        validationValue,
        at: checkedAt,
        evidence: "Unauthenticated Ollama loopback API status"
      ),
      runtime: observation(
        runtimeValue,
        at: checkedAt,
        expiresAt: checkedAt.addingTimeInterval(15),
        evidence: "Ollama /api/ps"
      ),
      estimatedMemory: memoryEstimate(for: installation),
      blockers: blockers
    )
  }

  private func supportsArchitecture(_ architecture: String) -> Bool {
    architecture == "arm64" || architecture == "arm64e"
  }

  public func makeTestPlan(
    for installation: ModelInstallation,
    context: RuntimeLaunchContext
  ) async throws -> RuntimeTestPlan {
    guard supportedFormats.contains(installation.variant.format) else {
      throw RuntimeAdapterError.unsupportedFormat(installation.variant.format)
    }
    guard let modelName = modelName(for: installation) else {
      throw RuntimeAdapterError.invalidToolDefinition
    }
    return RuntimeTestPlan(
      id: UUID(),
      adapterID: id,
      installationID: installation.id,
      createdAt: context.now,
      expiresAt: context.now.addingTimeInterval(120),
      endpoint: endpoint,
      strategy: .providerManaged(endpoint: endpoint, externalIdentifier: modelName),
      stopBehavior: .providerStopUnavailable,
      estimatedMemory: memoryEstimate(for: installation)
    )
  }

  public func healthCheck(endpoint: URL) async -> RuntimeProbeResult {
    do {
      _ = try await transport.availableModelNames()
      return RuntimeProbeResult(succeeded: true, checkedAt: .now, summary: "Ollama API reached")
    } catch {
      return RuntimeProbeResult(
        succeeded: false,
        checkedAt: .now,
        summary: "Ollama API did not answer"
      )
    }
  }

  public func inferenceCheck(
    endpoint: URL,
    installation: ModelInstallation,
    prompt: String
  ) async -> RuntimeProbeResult {
    guard let modelName = modelName(for: installation) else {
      return RuntimeProbeResult(
        succeeded: false,
        checkedAt: .now,
        summary: "Ollama model identifier is unavailable"
      )
    }
    do {
      let response = try await transport.generate(model: modelName, prompt: prompt)
      return RuntimeProbeResult(
        succeeded: true,
        checkedAt: .now,
        summary: "Ollama completed a one-token inference request",
        responseExcerpt: String(response.prefix(200))
      )
    } catch {
      return RuntimeProbeResult(
        succeeded: false,
        checkedAt: .now,
        summary: "Ollama inference request failed"
      )
    }
  }

  private func modelName(for installation: ModelInstallation) -> String? {
    let components = installation.rootURL.standardizedFileURL.pathComponents
    guard let manifestsIndex = components.lastIndex(of: "manifests") else { return nil }
    let location = Array(components.dropFirst(manifestsIndex + 1))
    guard location.count >= 4, let tag = location.last else { return nil }
    var modelComponents = Array(location.dropFirst().dropLast())
    if modelComponents.first == "library" { modelComponents.removeFirst() }
    guard !modelComponents.isEmpty else { return nil }
    return modelComponents.joined(separator: "/") + ":" + tag
  }

  private func contains(_ modelName: String, in names: Set<String>) -> Bool {
    let normalized = modelName.lowercased()
    let withoutLatest =
      normalized.hasSuffix(":latest")
      ? String(normalized.dropLast(":latest".count)) : normalized
    return names.contains(normalized) || names.contains(withoutLatest)
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
      basis: "Model weights plus 20% or 512 MB runtime overhead; estimate only"
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
