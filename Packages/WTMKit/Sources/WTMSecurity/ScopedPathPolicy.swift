import Foundation
import WTMDomain

public enum ScopedPathError: Error, Equatable, Sendable {
  case candidateOutsideRoot
  case unreadablePath
  case sourceIdentityUnavailable
  case sourceIdentityChanged
}

/// Prevents adapters from following a resolved path outside the configured scan root.
public struct ScopedPathPolicy: Sendable {
  public let rootURL: URL
  private let resolvedRootPath: String
  private let volumeIdentity: VolumeIdentity?
  private let expectedRootIdentity: SourceRootIdentity?

  public init(
    rootURL: URL,
    volumeIdentity: VolumeIdentity? = nil,
    expectedRootIdentity: SourceRootIdentity? = nil
  ) {
    let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    self.rootURL = rootURL
    self.volumeIdentity = volumeIdentity
    self.expectedRootIdentity = expectedRootIdentity
    resolvedRootPath = resolvedRoot.path
  }

  public func revalidateRoot() throws {
    guard let expectedRootIdentity else {
      throw ScopedPathError.sourceIdentityUnavailable
    }
    do {
      try SourceRootPolicy().revalidate(
        rootURL: rootURL,
        volumeIdentity: volumeIdentity,
        expected: expectedRootIdentity
      )
    } catch {
      throw ScopedPathError.sourceIdentityChanged
    }
  }

  public func validate(_ candidateURL: URL) throws -> URL {
    if expectedRootIdentity != nil {
      try revalidateRoot()
    }
    let resolvedCandidate = try validateAgainstCapturedRoot(candidateURL)
    if expectedRootIdentity != nil {
      try revalidateRoot()
    }
    return resolvedCandidate
  }

  /// Used only while a walker holds the same preflighted policy for one enumeration.
  func validateAgainstCapturedRoot(_ candidateURL: URL) throws -> URL {
    let resolvedCandidate = candidateURL.standardizedFileURL.resolvingSymlinksInPath()
    let candidatePath = resolvedCandidate.path
    let rootPrefix = resolvedRootPath.hasSuffix("/") ? resolvedRootPath : resolvedRootPath + "/"

    guard candidatePath == resolvedRootPath || candidatePath.hasPrefix(rootPrefix) else {
      throw ScopedPathError.candidateOutsideRoot
    }
    guard FileManager.default.isReadableFile(atPath: candidatePath) else {
      throw ScopedPathError.unreadablePath
    }
    return resolvedCandidate
  }
}
