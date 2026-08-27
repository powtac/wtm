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

  public func entries(
    under rootURL: URL,
    approvedBy source: ScanSource,
    descendIntoSubdirectories: Bool = true
  ) throws
    -> [FileSystemEntry]
  {
    var entries: [FileSystemEntry] = []
    try visitEntries(
      under: rootURL,
      approvedBy: source,
      descendIntoSubdirectories: descendIntoSubdirectories
    ) {
      entries.append($0)
      return true
    }
    return entries
  }

  /// Visits entries synchronously and stops when the visitor returns false.
  /// Use this for security budgets: unlike AsyncStream it cannot buffer ahead.
  public func visitEntries(
    under rootURL: URL,
    approvedBy source: ScanSource,
    descendIntoSubdirectories: Bool = true,
    visitor: (FileSystemEntry) throws -> Bool
  ) throws {
    try enumerate(
      under: rootURL,
      approvedBy: source,
      descendIntoSubdirectories: descendIntoSubdirectories,
      visitor: visitor
    )
  }

  /// Produces validated entries as traversal advances so adapters can publish bounded results.
  public func entryStream(
    under rootURL: URL,
    approvedBy source: ScanSource,
    descendIntoSubdirectories: Bool = true
  ) -> AsyncThrowingStream<FileSystemEntry, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try visitEntries(
            under: rootURL,
            approvedBy: source,
            descendIntoSubdirectories: descendIntoSubdirectories
          ) { entry in
            continuation.yield(entry)
            return true
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
    descendIntoSubdirectories: Bool,
    visitor: (FileSystemEntry) throws -> Bool
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
    var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
    if !descendIntoSubdirectories { options.insert(.skipsSubdirectoryDescendants) }
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: keys,
        options: options,
        errorHandler: { _, _ in true }
      )
    else {
      throw DirectoryWalkerError.enumerationFailed
    }

    for case let url as URL in enumerator {
      let shouldContinue = try autoreleasepool {
        try Task.checkCancellation()
        try policy.revalidateRoot()
        let values: URLResourceValues
        do {
          values = try url.resourceValues(forKeys: Set(keys))
        } catch {
          return true
        }

        let isSymbolicLink = values.isSymbolicLink ?? false
        if isSymbolicLink {
          enumerator.skipDescendants()
        }

        let resolvedURL: URL
        do {
          resolvedURL = try policy.validateAgainstCapturedRoot(url)
        } catch {
          return true
        }
        try policy.revalidateRoot()

        return try visitor(
          FileSystemEntry(
            url: url,
            resolvedURL: resolvedURL,
            isDirectory: values.isDirectory ?? false,
            isRegularFile: values.isRegularFile ?? false,
            isSymbolicLink: isSymbolicLink
          )
        )
      }
      if !shouldContinue { break }
    }
    try policy.revalidateRoot()
  }
}
