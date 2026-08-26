import Darwin
import Foundation
import WTMDomain

public enum SourceRootPolicyError: Error, Equatable, Sendable {
  case rootMissing
  case rootIsSymbolicLink
  case rootIsNotDirectory
  case volumeIdentityUnavailable
  case volumeChanged
  case pathChanged
  case identityChanged
}

/// Captures and revalidates the no-follow filesystem identity granted by the user.
public struct SourceRootPolicy: Sendable {
  public init() {}

  public func capture(
    rootURL: URL,
    volumeIdentity: VolumeIdentity? = nil
  ) throws -> SourceRootIdentity {
    let root = rootURL.standardizedFileURL
    let volume = try resolvedVolume(for: root, expected: volumeIdentity)
    let relativePath = try relativePath(of: root, under: volume.url)
    let components = pathURLs(relativePath: relativePath, volumeURL: volume.url)
    guard let rootInformation = try information(for: root) else {
      throw SourceRootPolicyError.rootMissing
    }
    guard !isSymbolicLink(rootInformation.mode) else {
      throw SourceRootPolicyError.rootIsSymbolicLink
    }
    guard isDirectory(rootInformation.mode) else {
      throw SourceRootPolicyError.rootIsNotDirectory
    }
    return SourceRootIdentity(
      volumeIdentifier: volume.identifier,
      rootRelativePath: relativePath,
      pathIdentities: try components.map { url, path in
        guard let information = try information(for: url) else {
          throw SourceRootPolicyError.rootMissing
        }
        return SourcePathIdentity(
          relativePath: path,
          fileID: information.fileID,
          mode: information.mode & UInt32(S_IFMT)
        )
      }
    )
  }

  public func revalidate(
    rootURL: URL,
    volumeIdentity: VolumeIdentity?,
    expected: SourceRootIdentity
  ) throws {
    let current = try capture(rootURL: rootURL, volumeIdentity: volumeIdentity)
    guard current.volumeIdentifier == expected.volumeIdentifier else {
      throw SourceRootPolicyError.volumeChanged
    }
    guard current.rootRelativePath == expected.rootRelativePath else {
      throw SourceRootPolicyError.pathChanged
    }
    guard current.pathIdentities == expected.pathIdentities else {
      throw SourceRootPolicyError.identityChanged
    }
  }

  private func resolvedVolume(
    for rootURL: URL,
    expected: VolumeIdentity?
  ) throws -> (url: URL, identifier: String) {
    let rootPath = rootURL.path
    let candidates =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeIdentifierKey, .volumeUUIDStringKey],
        options: [.skipHiddenVolumes]
      ) ?? []
    guard
      let volumeURL = candidates.filter({ candidate in
        let path = candidate.standardizedFileURL.path
        return rootPath == path || rootPath.hasPrefix(path == "/" ? "/" : path + "/")
      }).max(by: { $0.path.count < $1.path.count }),
      let values = try? volumeURL.resourceValues(
        forKeys: [.volumeIdentifierKey, .volumeUUIDStringKey]
      ),
      let rawIdentifier = values.volumeIdentifier
    else {
      throw SourceRootPolicyError.volumeIdentityUnavailable
    }
    let identifier = values.volumeUUIDString ?? String(describing: rawIdentifier)
    if let expected, expected.identifier != identifier {
      throw SourceRootPolicyError.volumeChanged
    }
    return (volumeURL.standardizedFileURL, identifier)
  }

  private func relativePath(of rootURL: URL, under volumeURL: URL) throws -> String {
    let rootPath = rootURL.path
    let volumePath = volumeURL.path
    guard rootPath == volumePath || rootPath.hasPrefix(volumePath == "/" ? "/" : volumePath + "/")
    else {
      throw SourceRootPolicyError.pathChanged
    }
    return String(rootPath.dropFirst(volumePath == "/" ? 1 : volumePath.count))
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  private func pathURLs(relativePath: String, volumeURL: URL) -> [(URL, String)] {
    var result: [(URL, String)] = []
    var url = volumeURL
    var path = ""
    result.append((url, path))
    for component in relativePath.split(separator: "/").map(String.init) {
      path = path.isEmpty ? component : path + "/" + component
      url.append(path: component, directoryHint: .isDirectory)
      result.append((url, path))
    }
    return result
  }

  private func information(for url: URL) throws -> (fileID: UInt64, mode: UInt32)? {
    var value = stat()
    guard lstat(url.path, &value) == 0 else {
      if errno == ENOENT || errno == ENOTDIR { return nil }
      throw SourceRootPolicyError.rootMissing
    }
    return (UInt64(value.st_ino), UInt32(value.st_mode))
  }

  private func isSymbolicLink(_ mode: UInt32) -> Bool {
    mode & UInt32(S_IFMT) == UInt32(S_IFLNK)
  }

  private func isDirectory(_ mode: UInt32) -> Bool {
    mode & UInt32(S_IFMT) == UInt32(S_IFDIR)
  }
}
