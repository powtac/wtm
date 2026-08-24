import Darwin
import Foundation
import WTMDomain

public enum DeletionTargetPolicyError: Error, Equatable, Sendable {
  case sourceRootTargeted
  case targetOutsideSource
  case targetMissing
  case identityChanged
}

/// Validates a deletion target lexically and reads its no-follow identity with `lstat`.
public struct DeletionTargetPolicy: Sendable {
  public init() {}

  public func captureIdentity(for targetURL: URL, under sourceRootURL: URL) throws
    -> DeletionFileIdentity
  {
    try validateContainment(of: targetURL, under: sourceRootURL)
    return try readIdentity(for: targetURL)
  }

  public func revalidate(_ target: DeletionFileTarget) throws {
    try validateContainment(of: target.url, under: target.sourceRootURL)
    let currentIdentity = try readIdentity(for: target.url)
    guard currentIdentity == target.identity else {
      throw DeletionTargetPolicyError.identityChanged
    }
  }

  public func validateContainment(of targetURL: URL, under sourceRootURL: URL) throws {
    let rootPath = sourceRootURL.standardizedFileURL.path
    let targetPath = targetURL.standardizedFileURL.path
    guard targetPath != rootPath else {
      throw DeletionTargetPolicyError.sourceRootTargeted
    }
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard targetPath.hasPrefix(rootPrefix) else {
      throw DeletionTargetPolicyError.targetOutsideSource
    }
  }

  private func readIdentity(for url: URL) throws -> DeletionFileIdentity {
    var information = stat()
    guard lstat(url.path, &information) == 0 else {
      throw DeletionTargetPolicyError.targetMissing
    }
    return DeletionFileIdentity(
      deviceID: UInt64(information.st_dev),
      fileID: UInt64(information.st_ino),
      mode: UInt32(information.st_mode),
      byteCount: Int64(information.st_size),
      modificationSeconds: Int64(information.st_mtimespec.tv_sec),
      modificationNanoseconds: Int64(information.st_mtimespec.tv_nsec)
    )
  }
}
