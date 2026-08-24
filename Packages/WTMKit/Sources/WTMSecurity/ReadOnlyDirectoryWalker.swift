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

    var entries: [FileSystemEntry] = []
    for case let url as URL in enumerator {
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

      entries.append(
        FileSystemEntry(
          url: url,
          resolvedURL: resolvedURL,
          isDirectory: values.isDirectory ?? false,
          isRegularFile: values.isRegularFile ?? false,
          isSymbolicLink: isSymbolicLink
        )
      )
    }
    return entries
  }
}
