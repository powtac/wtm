import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

/// Browser handoff only. Authentication stays in the browser; WTM reads no WebUI secrets.
public struct OpenWebUIClientAdapter: ClientAdapter {
  public let id = ClientAdapterID.openWebUI
  public let displayName = "Open WebUI"
  public let version = "1"
  private let connection: @Sendable (String) -> LocalModelConnection?

  public init(connection: @escaping @Sendable (String) -> LocalModelConnection?) {
    self.connection = connection
  }

  public func availability(for installation: ModelInstallation, context: ClientHandoffContext)
    -> ClientAvailability
  {
    if (try? makeHandoffPlan(for: installation, context: context)) != nil {
      return .available(
        summary:
          "Open the configured local WebUI with your model ID. Sign in in the browser if required; no prompt is sent."
      )
    }
    return .unavailable(
      reason:
        "Configure a local WebUI endpoint and exact model ID, then verify this installation through a local runtime."
    )
  }

  public func makeHandoffPlan(for installation: ModelInstallation, context: ClientHandoffContext)
    throws -> ClientHandoffPlan
  {
    guard installation.state == .stored, !installation.artifacts.contains(where: \.isPartial),
      let config = connection(installation.id)
    else { throw ClientAdapterError.unsupportedInstallation }
    try LocalModelConnectionPolicy().validate(config)
    let evidenceExpiry = context.runtimeInstances.filter {
      $0.installationID == installation.id && $0.state == .running
        && $0.lastInferenceCheck?.value == .inferenceVerified
    }.compactMap { $0.lastInferenceCheck?.expiresAt }.max()
    guard let evidenceExpiry, evidenceExpiry > context.now else {
      throw ClientAdapterError.verifiedRuntimeRequired
    }
    guard var components = URLComponents(url: config.endpoint, resolvingAgainstBaseURL: false)
    else {
      throw ClientAdapterError.invalidEndpoint
    }
    components.path = "/"
    components.queryItems = [URLQueryItem(name: "model", value: config.modelReference)]
    guard let url = components.url else { throw ClientAdapterError.invalidEndpoint }
    return ClientHandoffPlan(
      adapterID: id, installationID: installation.id,
      modelReference: config.modelReference, createdAt: context.now,
      expiresAt: min(context.now.addingTimeInterval(120), evidenceExpiry),
      endpoint: config.endpoint,
      strategy: .openURL(url))
  }
}
