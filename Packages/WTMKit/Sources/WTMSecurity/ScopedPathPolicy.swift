import Foundation

public enum ScopedPathError: Error, Equatable, Sendable {
  case candidateOutsideRoot
  case unreadablePath
}

/// Prevents adapters from following a resolved path outside the configured scan root.
public struct ScopedPathPolicy: Sendable {
  public let rootURL: URL
  private let resolvedRootPath: String

  public init(rootURL: URL) {
    let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    self.rootURL = rootURL
    resolvedRootPath = resolvedRoot.path
  }

  public func validate(_ candidateURL: URL) throws -> URL {
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
