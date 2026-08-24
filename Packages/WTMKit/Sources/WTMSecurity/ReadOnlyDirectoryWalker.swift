import Foundation

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

  public func entries(under rootURL: URL) throws -> [FileSystemEntry] {
    var entries: [FileSystemEntry] = []
    try enumerate(under: rootURL) { entries.append($0) }
    return entries
  }

  /// Produces validated entries as traversal advances so adapters can publish bounded results.
  public func entryStream(under rootURL: URL) -> AsyncThrowingStream<FileSystemEntry, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          try enumerate(under: rootURL) { entry in
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
    yield: (FileSystemEntry) -> Void
  ) throws {
    let policy = ScopedPathPolicy(rootURL: rootURL)
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
        resolvedURL = try policy.validate(url)
      } catch {
        continue
      }

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
  }
}
