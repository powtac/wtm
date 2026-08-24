import Foundation

public struct RuntimeArgumentValues: Hashable, Codable, Sendable {
  public let modelPath: String?
  public let modelID: String?
  public let endpoint: String?
  public let port: UInt16?
  public let configPath: String?

  public init(
    modelPath: String? = nil,
    modelID: String? = nil,
    endpoint: String? = nil,
    port: UInt16? = nil,
    configPath: String? = nil
  ) {
    self.modelPath = modelPath
    self.modelID = modelID
    self.endpoint = endpoint
    self.port = port
    self.configPath = configPath
  }
}

public struct RuntimeExecutableInvocation: Hashable, Codable, Sendable {
  public let executableURL: URL
  public let arguments: [String]
  public let currentDirectoryURL: URL?
  public let environment: [String: String]
  public let approvedIdentity: ExecutableIdentity

  public init(
    executableURL: URL,
    arguments: [String],
    currentDirectoryURL: URL? = nil,
    environment: [String: String] = [:],
    approvedIdentity: ExecutableIdentity
  ) {
    self.executableURL = executableURL
    self.arguments = arguments
    self.currentDirectoryURL = currentDirectoryURL
    self.environment = environment
    self.approvedIdentity = approvedIdentity
  }
}

public enum RuntimeLaunchStrategy: Hashable, Codable, Sendable {
  case providerManaged(endpoint: URL, externalIdentifier: String?)
  case executable(RuntimeExecutableInvocation)
}

public struct RuntimeTestPlan: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let adapterID: RuntimeAdapterID
  public let installationID: ModelInstallation.ID
  public let createdAt: Date
  public let expiresAt: Date
  public let endpoint: URL
  public let strategy: RuntimeLaunchStrategy
  public let stopBehavior: RuntimeStopBehavior
  public let estimatedMemory: RuntimeMemoryEstimate?

  public init(
    id: UUID,
    adapterID: RuntimeAdapterID,
    installationID: ModelInstallation.ID,
    createdAt: Date,
    expiresAt: Date,
    endpoint: URL,
    strategy: RuntimeLaunchStrategy,
    stopBehavior: RuntimeStopBehavior,
    estimatedMemory: RuntimeMemoryEstimate? = nil
  ) {
    self.id = id
    self.adapterID = adapterID
    self.installationID = installationID
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.endpoint = endpoint
    self.strategy = strategy
    self.stopBehavior = stopBehavior
    self.estimatedMemory = estimatedMemory
  }
}

public struct RuntimeProbeResult: Hashable, Codable, Sendable {
  public let succeeded: Bool
  public let checkedAt: Date
  public let summary: String
  public let responseExcerpt: String?

  public init(
    succeeded: Bool,
    checkedAt: Date,
    summary: String,
    responseExcerpt: String? = nil
  ) {
    self.succeeded = succeeded
    self.checkedAt = checkedAt
    self.summary = summary
    self.responseExcerpt = responseExcerpt
  }
}
