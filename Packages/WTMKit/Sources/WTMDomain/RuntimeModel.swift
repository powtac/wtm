import Foundation

public struct RuntimeAdapterID: RawRepresentable, Hashable, Codable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

extension RuntimeAdapterID {
  public static let ollama = RuntimeAdapterID(rawValue: "ollama")
  public static let llamaCpp = RuntimeAdapterID(rawValue: "llama-cpp")
}

public enum ModelIntegrity: String, Codable, CaseIterable, Sendable {
  case unknown
  case partial
  case complete
  case corrupt
  case orphaned
}

public enum RuntimeCompatibility: String, Codable, CaseIterable, Sendable {
  case unknown
  case runtimeNotInstalled
  case runtimeUnavailable
  case unsupportedFormat
  case unsupportedArchitecture
  case insufficientMemory
  case compatible
}

public enum ModelValidation: String, Codable, CaseIterable, Sendable {
  case untested
  case blocked
  case staticCompatible
  case runtimeReachable
  case inferenceVerified
  case inferenceFailed
}

public enum RuntimeState: String, Codable, CaseIterable, Sendable {
  case stopped
  case starting
  case running
  case stopping
  case failed
}

public enum RuntimeOwnership: String, Codable, CaseIterable, Sendable {
  case startedByWTM
  case providerManaged
}

public enum RuntimeStopBehavior: String, Codable, CaseIterable, Sendable {
  case stopOwnedProcess
  case providerStopUnavailable
  case stopProviderInstance
}

public struct RuntimeObservation<Value>: Hashable, Codable, Sendable
where Value: Hashable & Codable & Sendable {
  public let value: Value
  public let adapterID: RuntimeAdapterID
  public let adapterVersion: String
  public let checkedAt: Date
  public let expiresAt: Date?
  public let evidence: String

  public init(
    value: Value,
    adapterID: RuntimeAdapterID,
    adapterVersion: String,
    checkedAt: Date,
    expiresAt: Date? = nil,
    evidence: String
  ) {
    self.value = value
    self.adapterID = adapterID
    self.adapterVersion = adapterVersion
    self.checkedAt = checkedAt
    self.expiresAt = expiresAt
    self.evidence = evidence
  }

  public func isExpired(at date: Date) -> Bool {
    guard let expiresAt else { return false }
    return date >= expiresAt
  }
}

public struct RuntimeMemoryEstimate: Hashable, Codable, Sendable {
  public let byteCount: Int64
  public let contextTokenCount: Int?
  public let basis: String

  public init(byteCount: Int64, contextTokenCount: Int? = nil, basis: String) {
    self.byteCount = max(byteCount, 0)
    self.contextTokenCount = contextTokenCount
    self.basis = basis
  }
}

public struct RuntimeReadiness: Hashable, Codable, Sendable {
  public let installationID: ModelInstallation.ID
  public let adapterID: RuntimeAdapterID
  public let integrity: RuntimeObservation<ModelIntegrity>
  public let compatibility: RuntimeObservation<RuntimeCompatibility>
  public let validation: RuntimeObservation<ModelValidation>
  public let runtime: RuntimeObservation<RuntimeState>
  public let estimatedMemory: RuntimeMemoryEstimate?
  public let blockers: [String]

  public init(
    installationID: ModelInstallation.ID,
    adapterID: RuntimeAdapterID,
    integrity: RuntimeObservation<ModelIntegrity>,
    compatibility: RuntimeObservation<RuntimeCompatibility>,
    validation: RuntimeObservation<ModelValidation>,
    runtime: RuntimeObservation<RuntimeState>,
    estimatedMemory: RuntimeMemoryEstimate? = nil,
    blockers: [String] = []
  ) {
    self.installationID = installationID
    self.adapterID = adapterID
    self.integrity = integrity
    self.compatibility = compatibility
    self.validation = validation
    self.runtime = runtime
    self.estimatedMemory = estimatedMemory
    self.blockers = blockers
  }
}

public struct RuntimeInstance: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let adapterID: RuntimeAdapterID
  public let installationID: ModelInstallation.ID
  public let externalIdentifier: String?
  public let endpoint: URL
  public let state: RuntimeState
  public let startedAt: Date?
  public let ownership: RuntimeOwnership
  public let lastHealthCheck: RuntimeObservation<ModelValidation>?
  public let lastInferenceCheck: RuntimeObservation<ModelValidation>?

  public init(
    id: UUID,
    adapterID: RuntimeAdapterID,
    installationID: ModelInstallation.ID,
    externalIdentifier: String? = nil,
    endpoint: URL,
    state: RuntimeState,
    startedAt: Date? = nil,
    ownership: RuntimeOwnership,
    lastHealthCheck: RuntimeObservation<ModelValidation>? = nil,
    lastInferenceCheck: RuntimeObservation<ModelValidation>? = nil
  ) {
    self.id = id
    self.adapterID = adapterID
    self.installationID = installationID
    self.externalIdentifier = externalIdentifier
    self.endpoint = endpoint
    self.state = state
    self.startedAt = startedAt
    self.ownership = ownership
    self.lastHealthCheck = lastHealthCheck
    self.lastInferenceCheck = lastInferenceCheck
  }
}

public enum ToolRole: String, Codable, CaseIterable, Sendable {
  case runtime
  case client
}

public enum ToolDefinitionOrigin: String, Codable, CaseIterable, Sendable {
  case builtIn
  case userCreated
  case imported
}

public enum ToolPlaceholder: String, Codable, CaseIterable, Sendable {
  case modelPath
  case modelID = "modelId"
  case endpoint
  case port
  case configPath
}

public enum ToolArgument: Hashable, Codable, Sendable {
  case literal(String)
  case placeholder(ToolPlaceholder)
}

public enum ToolSigningStatus: String, Codable, CaseIterable, Sendable {
  case unsigned
  case adHoc
  case signed
  case invalid
  case unknown
}

public struct ExecutableIdentity: Hashable, Codable, Sendable {
  public let requestedURL: URL
  public let canonicalURL: URL
  public let deviceID: UInt64
  public let fileID: UInt64
  public let ownerUserID: UInt32
  public let ownerGroupID: UInt32
  public let mode: UInt32
  public let byteCount: Int64
  public let modificationSeconds: Int64
  public let modificationNanoseconds: Int64
  public let symbolicLinkDeviceID: UInt64?
  public let symbolicLinkFileID: UInt64?
  public let symbolicLinkModificationSeconds: Int64?
  public let symbolicLinkModificationNanoseconds: Int64?

  public init(
    requestedURL: URL,
    canonicalURL: URL,
    deviceID: UInt64,
    fileID: UInt64,
    ownerUserID: UInt32,
    ownerGroupID: UInt32,
    mode: UInt32,
    byteCount: Int64,
    modificationSeconds: Int64,
    modificationNanoseconds: Int64,
    symbolicLinkDeviceID: UInt64? = nil,
    symbolicLinkFileID: UInt64? = nil,
    symbolicLinkModificationSeconds: Int64? = nil,
    symbolicLinkModificationNanoseconds: Int64? = nil
  ) {
    self.requestedURL = requestedURL
    self.canonicalURL = canonicalURL
    self.deviceID = deviceID
    self.fileID = fileID
    self.ownerUserID = ownerUserID
    self.ownerGroupID = ownerGroupID
    self.mode = mode
    self.byteCount = byteCount
    self.modificationSeconds = modificationSeconds
    self.modificationNanoseconds = modificationNanoseconds
    self.symbolicLinkDeviceID = symbolicLinkDeviceID
    self.symbolicLinkFileID = symbolicLinkFileID
    self.symbolicLinkModificationSeconds = symbolicLinkModificationSeconds
    self.symbolicLinkModificationNanoseconds = symbolicLinkModificationNanoseconds
  }
}

public struct ToolValidationRecord: Hashable, Codable, Sendable {
  public let checkedAt: Date
  public let executableIdentity: ExecutableIdentity
  public let signingStatus: ToolSigningStatus
  public let signingIdentifier: String?
  public let version: String?
  public let binaryHash: String?

  public init(
    checkedAt: Date,
    executableIdentity: ExecutableIdentity,
    signingStatus: ToolSigningStatus,
    signingIdentifier: String? = nil,
    version: String? = nil,
    binaryHash: String? = nil
  ) {
    self.checkedAt = checkedAt
    self.executableIdentity = executableIdentity
    self.signingStatus = signingStatus
    self.signingIdentifier = signingIdentifier
    self.version = version
    self.binaryHash = binaryHash
  }
}

public struct ToolDefinition: Identifiable, Hashable, Codable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let id: UUID
  public let displayName: String
  public let role: ToolRole
  public let origin: ToolDefinitionOrigin
  public let isEnabled: Bool
  public let executableURL: URL
  public let arguments: [ToolArgument]
  public let supportedFormats: Set<ModelFormat>
  public let localAPIBaseURL: URL?
  public let currentDirectoryURL: URL?
  public let environment: [String: String]
  public let lastValidation: ToolValidationRecord?

  public init(
    schemaVersion: Int = ToolDefinition.currentSchemaVersion,
    id: UUID,
    displayName: String,
    role: ToolRole,
    origin: ToolDefinitionOrigin,
    isEnabled: Bool,
    executableURL: URL,
    arguments: [ToolArgument],
    supportedFormats: Set<ModelFormat>,
    localAPIBaseURL: URL? = nil,
    currentDirectoryURL: URL? = nil,
    environment: [String: String] = [:],
    lastValidation: ToolValidationRecord? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.displayName = displayName
    self.role = role
    self.origin = origin
    self.isEnabled = isEnabled
    self.executableURL = executableURL
    self.arguments = arguments
    self.supportedFormats = supportedFormats
    self.localAPIBaseURL = localAPIBaseURL
    self.currentDirectoryURL = currentDirectoryURL
    self.environment = environment
    self.lastValidation = lastValidation
  }
}

public struct ToolExecutionApproval: Hashable, Codable, Sendable {
  public let definitionID: ToolDefinition.ID
  public let executableIdentity: ExecutableIdentity
  public let arguments: [ToolArgument]
  public let currentDirectoryURL: URL?
  public let environment: [String: String]
  public let localAPIBaseURL: URL?
  public let approvedAt: Date

  public init(
    definition: ToolDefinition,
    executableIdentity: ExecutableIdentity,
    approvedAt: Date
  ) {
    definitionID = definition.id
    self.executableIdentity = executableIdentity
    arguments = definition.arguments
    currentDirectoryURL = definition.currentDirectoryURL
    environment = definition.environment
    localAPIBaseURL = definition.localAPIBaseURL
    self.approvedAt = approvedAt
  }

  public func matches(_ definition: ToolDefinition) -> Bool {
    definitionID == definition.id
      && executableIdentity.requestedURL == definition.executableURL.standardizedFileURL
      && arguments == definition.arguments
      && currentDirectoryURL == definition.currentDirectoryURL
      && environment == definition.environment
      && localAPIBaseURL == definition.localAPIBaseURL
  }
}
