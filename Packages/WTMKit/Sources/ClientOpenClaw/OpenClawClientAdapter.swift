import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

public struct OpenClawClientAdapter: ClientAdapter {
  public let id = ClientAdapterID.openClaw
  public let displayName = "OpenClaw"
  public let version = "1"

  private let nodeURL: URL?
  private let scriptURL: URL?
  private let environment: [String: String]
  private let inspector: ExecutableInspector
  private let endpointPolicy: LoopbackEndpointPolicy

  public init(
    nodeURL: URL?,
    scriptURL: URL?,
    environment: [String: String],
    inspector: ExecutableInspector = ExecutableInspector(),
    endpointPolicy: LoopbackEndpointPolicy = LoopbackEndpointPolicy()
  ) {
    self.nodeURL = nodeURL
    self.scriptURL = scriptURL
    self.environment = environment
    self.inspector = inspector
    self.endpointPolicy = endpointPolicy
  }

  public static func discovered(homeDirectory: URL) -> OpenClawClientAdapter {
    let fileManager = FileManager.default
    let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].map {
      URL(filePath: $0)
    }
    let scriptCandidates = [
      "/opt/homebrew/lib/node_modules/openclaw/openclaw.mjs",
      "/usr/local/lib/node_modules/openclaw/openclaw.mjs",
    ].map { URL(filePath: $0) }
    let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    return OpenClawClientAdapter(
      nodeURL: nodeCandidates.first { fileManager.isExecutableFile(atPath: $0.path) },
      scriptURL: scriptCandidates.first { fileManager.isExecutableFile(atPath: $0.path) },
      environment: [
        "HOME": homeDirectory.path,
        "LANG": "en_US.UTF-8",
        "PATH": path,
        "TMPDIR": fileManager.temporaryDirectory.path,
      ]
    )
  }

  public func availability(
    for installation: ModelInstallation,
    context: ClientHandoffContext
  ) -> ClientAvailability {
    guard installation.providerID == .ollama, installation.state == .stored else {
      return .unavailable(reason: "OpenClaw handoff currently requires a stored Ollama model.")
    }
    guard nodeURL != nil, scriptURL != nil else {
      return .unavailable(reason: "OpenClaw or its Node interpreter was not found.")
    }
    guard verifiedRuntime(for: installation, context: context) != nil else {
      return .unavailable(reason: "Verify this model through Ollama first.")
    }
    return .available(summary: "Send one local inference request through OpenClaw.")
  }

  public func makeHandoffPlan(
    for installation: ModelInstallation,
    context: ClientHandoffContext
  ) throws -> ClientHandoffPlan {
    guard installation.providerID == .ollama, installation.state == .stored else {
      throw ClientAdapterError.unsupportedInstallation
    }
    guard let nodeURL, let scriptURL else { throw ClientAdapterError.toolNotInstalled }
    guard let runtime = verifiedRuntime(for: installation, context: context) else {
      throw ClientAdapterError.verifiedRuntimeRequired
    }
    do {
      try endpointPolicy.validate(runtime.endpoint)
    } catch {
      throw ClientAdapterError.invalidEndpoint
    }
    let node: ExecutableInspection
    let script: ExecutableInspection
    do {
      node = try inspector.inspect(nodeURL)
      script = try inspector.inspect(scriptURL)
    } catch {
      throw ClientAdapterError.invalidTool
    }
    let reference = "ollama/\(ollamaModelReference(for: installation))"
    let invocation = RuntimeExecutableInvocation(
      executableURL: node.identity.requestedURL,
      arguments: [
        script.identity.canonicalURL.path,
        "infer", "model", "run", "--local", "--model", reference,
        "--prompt", "Reply with exactly: pong", "--json",
      ],
      environment: environment,
      approvedIdentity: node.identity
    )
    return ClientHandoffPlan(
      adapterID: id,
      installationID: installation.id,
      modelReference: reference,
      createdAt: context.now,
      expiresAt: context.now.addingTimeInterval(120),
      endpoint: runtime.endpoint,
      strategy: .executable(
        ClientExecutableHandoff(
          invocation: invocation,
          protectedResourceIdentities: [script.identity]
        )
      )
    )
  }

  private func verifiedRuntime(
    for installation: ModelInstallation,
    context: ClientHandoffContext
  ) -> RuntimeInstance? {
    context.runtimeInstances.first { runtime in
      runtime.installationID == installation.id
        && runtime.adapterID == .ollama
        && runtime.state == .running
        && runtime.lastInferenceCheck?.value == .inferenceVerified
        && runtime.lastInferenceCheck?.isExpired(at: context.now) == false
    }
  }

  private func ollamaModelReference(for installation: ModelInstallation) -> String {
    let tag = installation.variant.id.split(separator: ":").last.map(String.init)
    guard let tag, !tag.isEmpty else { return installation.identity.displayName }
    return "\(installation.identity.displayName):\(tag)"
  }
}
