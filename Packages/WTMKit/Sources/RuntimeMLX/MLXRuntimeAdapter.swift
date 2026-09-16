import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMRuntime
import WTMSecurity

public struct MLXRuntimeAdapter: RuntimeAdapter {
  public let id = RuntimeAdapterID.mlx
  public let displayName = "MLX"
  public let version = "1"
  public let supportedFormats: Set<ModelFormat> = [.mlx]
  public static let bundleIdentifier = "de.powtac.whatthemodel.mlxruntime"
  private let transport: any MLXRuntimeTransport

  public init(transport: any MLXRuntimeTransport = MLXHTTPRuntimeTransport()) {
    self.transport = transport
  }

  public static func definition(bundleURL: URL) -> ToolDefinition {
    ToolDefinition(
      id: UUID(), displayName: "WTM MLX Runtime", role: .runtime,
      runtimeAdapterID: .mlx, origin: .builtIn, isEnabled: false,
      executableURL: bundleURL.appending(path: "Contents/MacOS/wtm-mlx-runtime"),
      arguments: [
        .literal("--model"), .placeholder(.modelPath), .literal("--port"), .placeholder(.port),
      ],
      supportedFormats: [.mlx])
  }

  public func readiness(for installation: ModelInstallation, environment: RuntimeEnvironment) async
    -> RuntimeReadiness
  {
    let integrity: ModelIntegrity =
      installation.artifacts.contains(where: \.isPartial) || installation.state == .incomplete
      ? .partial : (installation.state == .stored ? .complete : .unknown)
    var compatibility = RuntimeCompatibility.compatible
    var blockers: [String] = []
    if !supportedFormats.contains(installation.variant.format) {
      compatibility = .unsupportedFormat
    } else if !["arm64", "arm64e"].contains(environment.architecture) {
      compatibility = .unsupportedArchitecture
    } else if (try? modelDirectory(installation)) == nil {
      compatibility = .invalidModel
    } else if let definition = environment.toolDefinition {
      if (try? inspectBundle(definition)) == nil {
        compatibility = .runtimeUnavailable
      } else if !definition.isEnabled {
        blockers.append("Enable the bundled WTM MLX Runtime before testing.")
      }
    } else {
      compatibility = .runtimeNotInstalled
    }
    let estimate = memoryEstimate(installation)
    if compatibility == .compatible, let capacity = environment.memoryCapacityByteCount,
      estimate.byteCount > capacity
    {
      compatibility = .insufficientMemory
    }
    if compatibility != .compatible {
      blockers.append(
        "MLX requires complete local weights and tokenizer.json, Apple Silicon, and the sealed WTM MLX Runtime bundle. Loose Python environments are unsupported."
      )
    }
    return RuntimeReadiness(
      installationID: installation.id, adapterID: id,
      integrity: observation(integrity), compatibility: observation(compatibility),
      validation: observation(
        compatibility == .compatible ? ModelValidation.staticCompatible : .blocked),
      runtime: observation(RuntimeState.stopped), estimatedMemory: estimate, blockers: blockers)
  }

  public func makeTestPlan(for installation: ModelInstallation, context: RuntimeLaunchContext)
    async throws -> RuntimeTestPlan
  {
    let model = try modelDirectory(installation)
    guard let definition = context.toolDefinition, let approval = context.toolApproval else {
      throw RuntimeAdapterError.executableNotApproved
    }
    let bundle = try inspectBundle(definition)
    let port = try context.port ?? LoopbackPortAllocator().availablePort()
    guard port >= 1024, let endpoint = URL(string: "http://127.0.0.1:\(port)") else {
      throw RuntimeAdapterError.endpointUnavailable
    }
    let base = try ToolInvocationBuilder().makeInvocation(
      definition: definition,
      values: RuntimeArgumentValues(modelPath: model.sourceURL.path, port: port),
      modelFormat: .mlx, approval: approval)
    guard base.arguments == ["--model", model.sourceURL.path, "--port", String(port)],
      base.environment.isEmpty, base.currentDirectoryURL == nil
    else {
      throw RuntimeAdapterError.invalidToolDefinition
    }
    let invocation = RuntimeExecutableInvocation(
      executableURL: base.executableURL,
      arguments: base.arguments, approvedIdentity: base.approvedIdentity,
      sealedBundle: bundle, modelDirectory: model)
    return RuntimeTestPlan(
      id: UUID(), adapterID: id, installationID: installation.id,
      createdAt: context.now, expiresAt: context.now.addingTimeInterval(120), endpoint: endpoint,
      strategy: .executable(invocation), stopBehavior: .stopOwnedProcess,
      estimatedMemory: memoryEstimate(installation))
  }

  public func healthCheck(endpoint: URL) async -> RuntimeProbeResult {
    do {
      try await transport.health(endpoint)
      return RuntimeProbeResult(
        succeeded: true, checkedAt: .now, summary: "Sealed MLX helper is ready.")
    } catch {
      return RuntimeProbeResult(
        succeeded: false, checkedAt: .now, summary: "MLX helper is not ready.")
    }
  }

  public func inferenceCheck(endpoint: URL, installation: ModelInstallation, prompt: String) async
    -> RuntimeProbeResult
  {
    do {
      let content = try await transport.complete(endpoint, prompt: prompt)
      return RuntimeProbeResult(
        succeeded: true, checkedAt: .now,
        summary: "MLX computed one token from the staged local model.", responseExcerpt: content)
    } catch {
      return RuntimeProbeResult(succeeded: false, checkedAt: .now, summary: "MLX inference failed.")
    }
  }

  private func inspectBundle(_ definition: ToolDefinition) throws -> RuntimeSealedBundle {
    let url = definition.executableURL.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    guard definition.runtimeAdapterID == .mlx,
      definition.executableURL.lastPathComponent == "wtm-mlx-runtime",
      Bundle(url: url)?.object(forInfoDictionaryKey: "WTMMLXProtocol") as? Int == 1
    else {
      throw RuntimeAdapterError.invalidToolDefinition
    }
    return try SignedRuntimeBundleInspector().inspect(url, identifier: Self.bundleIdentifier)
  }

  private func modelDirectory(_ installation: ModelInstallation) throws -> RuntimeModelDirectory {
    guard installation.variant.format == .mlx, installation.state == .stored,
      !installation.artifacts.contains(where: \.isPartial),
      installation.rootURL.isFileURL,
      installation.rootURL.resolvingSymlinksInPath().standardizedFileURL
        == installation.rootURL.standardizedFileURL
    else { throw RuntimeAdapterError.invalidToolDefinition }
    let root = installation.rootURL.standardizedFileURL
    let selected = installation.artifacts.filter {
      ["config.json", "generation_config.json", "tokenizer.json"].contains($0.url.lastPathComponent)
        || ($0.kind == .weights && $0.url.lastPathComponent.hasPrefix("model")
          && $0.url.pathExtension == "safetensors")
    }
    let names = selected.map { $0.url.lastPathComponent }
    guard names.contains("config.json"), names.contains("tokenizer.json"),
      names.contains(where: { $0.hasSuffix(".safetensors") }), Set(names).count == names.count,
      selected.count <= 4096,
      selected.allSatisfy({ $0.url.deletingLastPathComponent().standardizedFileURL == root })
    else { throw RuntimeAdapterError.invalidToolDefinition }
    let identities = try selected.sorted { $0.url.path < $1.url.path }.map {
      try FileMetadataReader().runtimePathIdentity(for: $0.url)
    }
    return RuntimeModelDirectory(sourceURL: root, resources: identities)
  }

  private func memoryEstimate(_ installation: ModelInstallation) -> RuntimeMemoryEstimate {
    let bytes = installation.artifacts.filter { $0.kind == .weights }.reduce(Int64(0)) {
      $0 + $1.logicalByteCount
    }
    return RuntimeMemoryEstimate(
      byteCount: bytes + max(bytes / 4, 536_870_912),
      basis:
        "MLX weights plus 25% or 512 MB overhead; a private model snapshot also needs disk space.")
  }

  private func observation<T: Hashable & Codable & Sendable>(_ value: T) -> RuntimeObservation<T> {
    RuntimeObservation(
      value: value, adapterID: id, adapterVersion: version, checkedAt: .now,
      expiresAt: Date.now.addingTimeInterval(15),
      evidence: "Static local model and sealed runtime inspection")
  }
}
