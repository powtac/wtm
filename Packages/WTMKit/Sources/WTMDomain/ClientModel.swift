import Foundation

public struct ClientAdapterID: RawRepresentable, Identifiable, Hashable, Codable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
  public var id: String { rawValue }
}

extension ClientAdapterID {
  public static let openClaw = ClientAdapterID(rawValue: "openclaw")
  public static let unsloth = ClientAdapterID(rawValue: "unsloth")
}

public enum ClientAvailability: Hashable, Sendable {
  case available(summary: String)
  case unavailable(reason: String)
}

public struct ClientHandoffContext: Hashable, Sendable {
  public let now: Date
  public let runtimeInstances: [RuntimeInstance]

  public init(now: Date = .now, runtimeInstances: [RuntimeInstance] = []) {
    self.now = now
    self.runtimeInstances = runtimeInstances
  }
}

public struct ClientExecutableHandoff: Hashable, Codable, Sendable {
  public let invocation: RuntimeExecutableInvocation
  public let protectedResourceIdentities: [ExecutableIdentity]

  public init(
    invocation: RuntimeExecutableInvocation,
    protectedResourceIdentities: [ExecutableIdentity]
  ) {
    self.invocation = invocation
    self.protectedResourceIdentities = protectedResourceIdentities
  }
}

public enum ClientHandoffStrategy: Hashable, Codable, Sendable {
  case executable(ClientExecutableHandoff)
  case openURL(URL)
}

public struct ClientHandoffPlan: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let adapterID: ClientAdapterID
  public let installationID: ModelInstallation.ID
  public let modelReference: String
  public let createdAt: Date
  public let expiresAt: Date
  public let endpoint: URL
  public let strategy: ClientHandoffStrategy

  public init(
    id: UUID = UUID(),
    adapterID: ClientAdapterID,
    installationID: ModelInstallation.ID,
    modelReference: String,
    createdAt: Date,
    expiresAt: Date,
    endpoint: URL,
    strategy: ClientHandoffStrategy
  ) {
    self.id = id
    self.adapterID = adapterID
    self.installationID = installationID
    self.modelReference = modelReference
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.endpoint = endpoint
    self.strategy = strategy
  }
}
