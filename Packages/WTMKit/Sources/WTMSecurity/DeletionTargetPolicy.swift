import Darwin
import Foundation
import WTMDomain

public enum DeletionTargetPolicyError: Error, Equatable, Sendable {
  case sourceRootTargeted
  case targetOutsideSource
  case targetMissing
  case identityChanged
  case sourceVolumeReadOnly
}

/// Validates a deletion target lexically and reads its no-follow identity with `lstat`.
public struct DeletionTargetPolicy: Sendable {
  private let volumeIsReadOnly: @Sendable (URL) throws -> Bool

  public init(
    volumeIsReadOnly: @escaping @Sendable (URL) throws -> Bool = { url in
      try url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly == true
    }
  ) {
    self.volumeIsReadOnly = volumeIsReadOnly
  }

  public func validateWritableVolume(containing sourceRootURL: URL) throws {
    guard try !volumeIsReadOnly(sourceRootURL) else {
      throw DeletionTargetPolicyError.sourceVolumeReadOnly
    }
  }

  public func captureIdentity(
    for targetURL: URL,
    under sourceRootURL: URL,
    volumeIdentity: VolumeIdentity?,
    expectedRootIdentity: SourceRootIdentity
  ) throws -> DeletionFileIdentity {
    let rootPolicy = SourceRootPolicy()
    try rootPolicy.revalidate(
      rootURL: sourceRootURL,
      volumeIdentity: volumeIdentity,
      expected: expectedRootIdentity
    )
    try validateResolvedContainment(
      of: targetURL,
      under: sourceRootURL,
      volumeIdentity: volumeIdentity,
      expectedRootIdentity: expectedRootIdentity
    )
    try validateContainment(of: targetURL, under: sourceRootURL)
    let identity = try readIdentity(for: targetURL)
    try rootPolicy.revalidate(
      rootURL: sourceRootURL,
      volumeIdentity: volumeIdentity,
      expected: expectedRootIdentity
    )
    return identity
  }

  public func revalidate(_ target: DeletionFileTarget) throws {
    let rootPolicy = SourceRootPolicy()
    try rootPolicy.revalidate(
      rootURL: target.sourceRootURL,
      volumeIdentity: nil,
      expected: target.sourceRootIdentity
    )
    try validateResolvedContainment(
      of: target.url,
      under: target.sourceRootURL,
      volumeIdentity: nil,
      expectedRootIdentity: target.sourceRootIdentity
    )
    try validateContainment(of: target.url, under: target.sourceRootURL)
    let currentIdentity = try readIdentity(for: target.url)
    try rootPolicy.revalidate(
      rootURL: target.sourceRootURL,
      volumeIdentity: nil,
      expected: target.sourceRootIdentity
    )
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

  private func validateResolvedContainment(
    of targetURL: URL,
    under sourceRootURL: URL,
    volumeIdentity: VolumeIdentity?,
    expectedRootIdentity: SourceRootIdentity
  ) throws {
    _ = try ScopedPathPolicy(
      rootURL: sourceRootURL,
      volumeIdentity: volumeIdentity,
      expectedRootIdentity: expectedRootIdentity
    ).validate(targetURL)
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
