import Foundation
import WTMDomain

public struct FileSystemEntry: Hashable, Sendable {
  public let url: URL
  public let resolvedURL: URL
  public let isDirectory: Bool
  public let isRegularFile: Bool
  public let isSymbolicLink: Bool

  public init(
    url: URL,
    resolvedURL: URL,
    isDirectory: Bool,
    isRegularFile: Bool,
    isSymbolicLink: Bool
  ) {
    self.url = url
    self.resolvedURL = resolvedURL
    self.isDirectory = isDirectory
    self.isRegularFile = isRegularFile
    self.isSymbolicLink = isSymbolicLink
  }
}

public enum DirectoryWalkerError: Error, Equatable, Sendable {
  case rootIsNotReadable
  case enumerationFailed
}

/// Enumerates a configured root without following symbolic links outside that root.
public struct ReadOnlyDirectoryWalker: Sendable {
  public init() {}

  public func entries(under rootURL: URL, approvedBy source: ScanSource) throws
    -> [FileSystemEntry]
  {
    var entries: [FileSystemEntry] = []
    try enumerate(under: rootURL, approvedBy: source) { entries.append($0) }
    return entries
  }

  /// Produces validated entries as traversal advances so adapters can publish bounded results.
  public func entryStream(
    under rootURL: URL,
    approvedBy source: ScanSource
  ) -> AsyncThrowingStream<FileSystemEntry, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try enumerate(under: rootURL, approvedBy: source) { entry in
            continuation.yield(entry)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func enumerate(
    under rootURL: URL,
    approvedBy source: ScanSource,
    yield: (FileSystemEntry) -> Void
  ) throws {
    guard let rootIdentity = source.rootIdentity else {
      throw ScopedPathError.sourceIdentityUnavailable
    }
    let policy = ScopedPathPolicy(
      rootURL: source.rootURL,
      volumeIdentity: source.volumeIdentity,
      expectedRootIdentity: rootIdentity
    )
    try policy.revalidateRoot()
    _ = try policy.validate(rootURL)
    guard FileManager.default.isReadableFile(atPath: rootURL.path) else {
      throw DirectoryWalkerError.rootIsNotReadable
    }

    let keys: [URLResourceKey] = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isSymbolicLinkKey,
    ]
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: keys,
        options: [.skipsPackageDescendants],
        errorHandler: { _, _ in true }
      )
    else {
      throw DirectoryWalkerError.enumerationFailed
    }

    for case let url as URL in enumerator {
      try Task.checkCancellation()
      try policy.revalidateRoot()
      let values: URLResourceValues
      do {
        values = try url.resourceValues(forKeys: Set(keys))
      } catch {
        continue
      }

      let isSymbolicLink = values.isSymbolicLink ?? false
      if isSymbolicLink {
        enumerator.skipDescendants()
      }

      let resolvedURL: URL
      do {
        resolvedURL = try policy.validateAgainstCapturedRoot(url)
      } catch {
        continue
      }
      try policy.revalidateRoot()

      yield(
        FileSystemEntry(
          url: url,
          resolvedURL: resolvedURL,
          isDirectory: values.isDirectory ?? false,
          isRegularFile: values.isRegularFile ?? false,
          isSymbolicLink: isSymbolicLink
        )
      )
    }
    try policy.revalidateRoot()
  }
}
