import Darwin
import Foundation
import Security
import WTMDomain

public enum ExecutableInspectionError: Error, Equatable, Sendable {
  case invalidURL
  case missing
  case unresolvedSymbolicLink
  case notRegularFile
  case notExecutable
  case unsafeOwner
  case unsafePermissions
  case unsafeAncestor
}

public struct ExecutableInspection: Hashable, Sendable {
  public let identity: ExecutableIdentity
  public let signingStatus: ToolSigningStatus
  public let signingIdentifier: String?
  public let version: String?

  public init(
    identity: ExecutableIdentity,
    signingStatus: ToolSigningStatus,
    signingIdentifier: String?,
    version: String?
  ) {
    self.identity = identity
    self.signingStatus = signingStatus
    self.signingIdentifier = signingIdentifier
    self.version = version
  }
}

public struct ExecutableInspector: Sendable {
  public init() {}

  public func inspect(_ requestedURL: URL) throws -> ExecutableInspection {
    guard requestedURL.isFileURL, requestedURL.path.hasPrefix("/"),
      !requestedURL.path.contains("\0")
    else {
      throw ExecutableInspectionError.invalidURL
    }

    var requestedInformation = stat()
    guard lstat(requestedURL.path, &requestedInformation) == 0 else {
      throw ExecutableInspectionError.missing
    }

    let isSymbolicLink = (requestedInformation.st_mode & S_IFMT) == S_IFLNK
    let canonicalURL = requestedURL.resolvingSymlinksInPath().standardizedFileURL
    if isSymbolicLink, canonicalURL == requestedURL.standardizedFileURL {
      throw ExecutableInspectionError.unresolvedSymbolicLink
    }

    var targetInformation = stat()
    guard lstat(canonicalURL.path, &targetInformation) == 0 else {
      throw ExecutableInspectionError.missing
    }
    guard (targetInformation.st_mode & S_IFMT) == S_IFREG else {
      throw ExecutableInspectionError.notRegularFile
    }
    guard (targetInformation.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0 else {
      throw ExecutableInspectionError.notExecutable
    }
    guard targetInformation.st_uid == getuid() || targetInformation.st_uid == 0 else {
      throw ExecutableInspectionError.unsafeOwner
    }
    guard (targetInformation.st_mode & (S_IWGRP | S_IWOTH)) == 0 else {
      throw ExecutableInspectionError.unsafePermissions
    }
    try validateAncestors(of: canonicalURL)

    let identity = ExecutableIdentity(
      requestedURL: requestedURL.standardizedFileURL,
      canonicalURL: canonicalURL,
      deviceID: UInt64(targetInformation.st_dev),
      fileID: UInt64(targetInformation.st_ino),
      ownerUserID: UInt32(targetInformation.st_uid),
      ownerGroupID: UInt32(targetInformation.st_gid),
      mode: UInt32(targetInformation.st_mode),
      byteCount: Int64(targetInformation.st_size),
      modificationSeconds: Int64(targetInformation.st_mtimespec.tv_sec),
      modificationNanoseconds: Int64(targetInformation.st_mtimespec.tv_nsec),
      symbolicLinkDeviceID: isSymbolicLink ? UInt64(requestedInformation.st_dev) : nil,
      symbolicLinkFileID: isSymbolicLink ? UInt64(requestedInformation.st_ino) : nil,
      symbolicLinkModificationSeconds: isSymbolicLink
        ? Int64(requestedInformation.st_mtimespec.tv_sec) : nil,
      symbolicLinkModificationNanoseconds: isSymbolicLink
        ? Int64(requestedInformation.st_mtimespec.tv_nsec) : nil
    )
    let signing = signingEvidence(for: canonicalURL)
    return ExecutableInspection(
      identity: identity,
      signingStatus: signing.status,
      signingIdentifier: signing.identifier,
      version: bundleVersion(for: canonicalURL)
    )
  }

  private func validateAncestors(of url: URL) throws {
    var directory = url.deletingLastPathComponent().standardizedFileURL
    while true {
      var information = stat()
      guard lstat(directory.path, &information) == 0,
        (information.st_mode & S_IFMT) == S_IFDIR
      else { throw ExecutableInspectionError.unsafeAncestor }
      guard information.st_uid == getuid() || information.st_uid == 0,
        (information.st_mode & (S_IWGRP | S_IWOTH)) == 0
      else { throw ExecutableInspectionError.unsafeAncestor }
      let parent = directory.deletingLastPathComponent().standardizedFileURL
      if parent == directory { return }
      directory = parent
    }
  }

  private func signingEvidence(for executableURL: URL) -> (
    status: ToolSigningStatus, identifier: String?
  ) {
    var staticCode: SecStaticCode?
    let creationStatus = SecStaticCodeCreateWithPath(executableURL as CFURL, [], &staticCode)
    guard creationStatus == errSecSuccess, let staticCode else {
      return (creationStatus == errSecCSUnsigned ? .unsigned : .unknown, nil)
    }

    let validityStatus = SecStaticCodeCheckValidity(staticCode, [], nil)
    guard validityStatus == errSecSuccess else {
      return (validityStatus == errSecCSUnsigned ? .unsigned : .invalid, nil)
    }

    var information: CFDictionary?
    let informationStatus = SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &information
    )
    guard informationStatus == errSecSuccess,
      let values = information as? [String: Any]
    else {
      return (.signed, nil)
    }
    let identifier = values[kSecCodeInfoIdentifier as String] as? String
    let flags = values[kSecCodeInfoFlags as String] as? UInt32 ?? 0
    // Security.framework does not expose the public CS_ADHOC bit to Swift.
    let isAdHoc = (flags & 0x0000_0002) != 0
    return (isAdHoc ? .adHoc : .signed, identifier)
  }

  private func bundleVersion(for executableURL: URL) -> String? {
    let components = executableURL.pathComponents
    guard let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }) else {
      return nil
    }
    let appPath = NSString.path(withComponents: Array(components[...appIndex]))
    guard let bundle = Bundle(path: appPath) else { return nil }
    return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
  }
}
