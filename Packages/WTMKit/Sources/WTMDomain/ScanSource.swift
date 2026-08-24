import Foundation

public enum SourceAccessState: String, Codable, CaseIterable, Sendable {
  case notSetUp
  case allowed
  case limited
  case denied
  case offline
  case stale
}

public struct VolumeIdentity: Hashable, Codable, Sendable {
  public let identifier: String
  public let relativePath: String

  public init(identifier: String, relativePath: String) {
    self.identifier = identifier
    self.relativePath = relativePath
  }
}

public struct ScanSource: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let displayName: String
  public let providerID: ProviderID
  public let rootURL: URL
  public let volumeIdentity: VolumeIdentity?
  public let accessState: SourceAccessState
  public let isEnabled: Bool

  public init(
    id: String,
    displayName: String,
    providerID: ProviderID,
    rootURL: URL,
    volumeIdentity: VolumeIdentity? = nil,
    accessState: SourceAccessState = .notSetUp,
    isEnabled: Bool = false
  ) {
    self.id = id
    self.displayName = displayName
    self.providerID = providerID
    self.rootURL = rootURL
    self.volumeIdentity = volumeIdentity
    self.accessState = accessState
    self.isEnabled = isEnabled
  }
}
