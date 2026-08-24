import Foundation

public enum ModelFormat: String, Codable, CaseIterable, Sendable {
  case gguf
  case safetensors
  case mlx
  case ollama
  case unknown
}

public enum InstallationState: String, Codable, CaseIterable, Sendable {
  case stored
  case incomplete
  case issue
  case offline
}

public enum EvidenceConfidence: String, Codable, CaseIterable, Sendable {
  case confirmed
  case derived
  case heuristic
  case unknown
}

public enum TimestampKind: String, Codable, CaseIterable, Sendable {
  case providerDownload
  case fileCreation
  case fileModification
  case observedThisScan
}

public struct ObservedTimestamp: Hashable, Codable, Sendable {
  public let value: Date
  public let kind: TimestampKind
  public let confidence: EvidenceConfidence

  public init(value: Date, kind: TimestampKind, confidence: EvidenceConfidence) {
    self.value = value
    self.kind = kind
    self.confidence = confidence
  }
}

public struct ModelIdentity: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let displayName: String
  public let family: String?

  public init(id: String, displayName: String, family: String? = nil) {
    self.id = id
    self.displayName = displayName
    self.family = family
  }
}

public struct ModelVariant: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let identityID: ModelIdentity.ID
  public let format: ModelFormat
  public let quantization: String?

  public init(
    id: String,
    identityID: ModelIdentity.ID,
    format: ModelFormat,
    quantization: String? = nil
  ) {
    self.id = id
    self.identityID = identityID
    self.format = format
    self.quantization = quantization
  }
}

public enum ArtifactKind: String, Codable, CaseIterable, Sendable {
  case weights
  case manifest
  case configuration
  case tokenizer
  case metadata
  case unknown
}

public struct Artifact: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let url: URL
  public let kind: ArtifactKind
  public let logicalByteCount: Int64
  public let allocatedByteCount: Int64
  public let physicalIdentifier: String?
  public let isShared: Bool
  public let isPartial: Bool

  public init(
    id: String,
    url: URL,
    kind: ArtifactKind,
    logicalByteCount: Int64,
    allocatedByteCount: Int64,
    physicalIdentifier: String? = nil,
    isShared: Bool = false,
    isPartial: Bool = false
  ) {
    self.id = id
    self.url = url
    self.kind = kind
    self.logicalByteCount = logicalByteCount
    self.allocatedByteCount = allocatedByteCount
    self.physicalIdentifier = physicalIdentifier
    self.isShared = isShared
    self.isPartial = isPartial
  }
}

public struct ModelCardLink: Hashable, Codable, Sendable {
  public let url: URL
  public let confidence: EvidenceConfidence
  public let evidence: String

  public init(url: URL, confidence: EvidenceConfidence, evidence: String) {
    self.url = url
    self.confidence = confidence
    self.evidence = evidence
  }
}

public struct ModelInstallation: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let identity: ModelIdentity
  public let variant: ModelVariant
  public let sourceID: ScanSource.ID
  public let providerID: ProviderID
  public let rootURL: URL
  public let state: InstallationState
  public let artifacts: [Artifact]
  public let configurationURLs: [URL]
  public let timestamps: [ObservedTimestamp]
  public let modelCard: ModelCardLink?

  public init(
    id: String,
    identity: ModelIdentity,
    variant: ModelVariant,
    sourceID: ScanSource.ID,
    providerID: ProviderID,
    rootURL: URL,
    state: InstallationState,
    artifacts: [Artifact],
    configurationURLs: [URL] = [],
    timestamps: [ObservedTimestamp] = [],
    modelCard: ModelCardLink? = nil
  ) {
    self.id = id
    self.identity = identity
    self.variant = variant
    self.sourceID = sourceID
    self.providerID = providerID
    self.rootURL = rootURL
    self.state = state
    self.artifacts = artifacts
    self.configurationURLs = configurationURLs
    self.timestamps = timestamps
    self.modelCard = modelCard
  }

  public var logicalByteCount: Int64 {
    artifacts.reduce(0) { $0 + $1.logicalByteCount }
  }

  public var allocatedByteCount: Int64 {
    artifacts.reduce(0) { $0 + $1.allocatedByteCount }
  }

  /// Earliest available local-model timestamp. Scan observation is excluded because it is not
  /// evidence of when the model first changed on disk.
  public var earliestChangeTimestamp: ObservedTimestamp? {
    timestamps
      .filter { $0.kind != .observedThisScan }
      .min { left, right in
        if left.value != right.value { return left.value < right.value }
        if left.confidence != right.confidence {
          return left.confidence.sortPriority < right.confidence.sortPriority
        }
        return left.kind.rawValue < right.kind.rawValue
      }
  }
}

private extension EvidenceConfidence {
  var sortPriority: Int {
    switch self {
    case .confirmed: 0
    case .derived: 1
    case .heuristic: 2
    case .unknown: 3
    }
  }
}
