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

/// Stable, no-follow identity of one path component inside an approved source scope.
public struct SourcePathIdentity: Hashable, Codable, Sendable {
  public let relativePath: String
  public let fileID: UInt64
  public let mode: UInt32

  public init(relativePath: String, fileID: UInt64, mode: UInt32) {
    self.relativePath = relativePath
    self.fileID = fileID
    self.mode = mode
  }
}

/// Consent-time identity of a source root and every mutable component below its volume root.
public struct SourceRootIdentity: Hashable, Codable, Sendable {
  public let volumeIdentifier: String
  public let rootRelativePath: String
  public let pathIdentities: [SourcePathIdentity]

  public init(
    volumeIdentifier: String,
    rootRelativePath: String,
    pathIdentities: [SourcePathIdentity]
  ) {
    self.volumeIdentifier = volumeIdentifier
    self.rootRelativePath = rootRelativePath
    self.pathIdentities = pathIdentities
  }
}

public struct ScanSource: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let displayName: String
  public let providerID: ProviderID
  public let rootURL: URL
  public let volumeIdentity: VolumeIdentity?
  public let rootIdentity: SourceRootIdentity?
  public let accessState: SourceAccessState
  public let isEnabled: Bool

  public init(
    id: String,
    displayName: String,
    providerID: ProviderID,
    rootURL: URL,
    volumeIdentity: VolumeIdentity? = nil,
    rootIdentity: SourceRootIdentity? = nil,
    accessState: SourceAccessState = .notSetUp,
    isEnabled: Bool = false
  ) {
    self.id = id
    self.displayName = displayName
    self.providerID = providerID
    self.rootURL = rootURL
    self.volumeIdentity = volumeIdentity
    self.rootIdentity = rootIdentity
    self.accessState = accessState
    self.isEnabled = isEnabled
  }
}
