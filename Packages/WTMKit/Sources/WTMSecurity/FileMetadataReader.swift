import Darwin
import Foundation
import WTMDomain

public struct FileMetadata: Hashable, Sendable {
  public let logicalByteCount: Int64
  public let allocatedByteCount: Int64
  public let physicalIdentifier: String?
  public let creationDate: Date?
  public let modificationDate: Date?
  public let isSymbolicLink: Bool

  public init(
    logicalByteCount: Int64,
    allocatedByteCount: Int64,
    physicalIdentifier: String?,
    creationDate: Date?,
    modificationDate: Date?,
    isSymbolicLink: Bool
  ) {
    self.logicalByteCount = logicalByteCount
    self.allocatedByteCount = allocatedByteCount
    self.physicalIdentifier = physicalIdentifier
    self.creationDate = creationDate
    self.modificationDate = modificationDate
    self.isSymbolicLink = isSymbolicLink
  }
}

/// Reads metadata only and never opens files for writing or hashes file contents.
public struct FileMetadataReader: Sendable {
  public init() {}

  public func identity(for url: URL) throws -> DeletionFileIdentity {
    var information = stat()
    guard stat(url.path, &information) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
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

  public func runtimePathIdentity(for url: URL) throws -> RuntimePathIdentity {
    let requestedURL = url.standardizedFileURL
    let canonicalURL = requestedURL.resolvingSymlinksInPath().standardizedFileURL
    let identity = try identity(for: canonicalURL)
    return RuntimePathIdentity(
      requestedURL: requestedURL,
      canonicalURL: canonicalURL,
      deviceID: identity.deviceID,
      fileID: identity.fileID,
      mode: identity.mode,
      byteCount: identity.byteCount,
      modificationSeconds: identity.modificationSeconds,
      modificationNanoseconds: identity.modificationNanoseconds
    )
  }

  public func validate(_ identity: RuntimePathIdentity) throws {
    guard try runtimePathIdentity(for: identity.requestedURL) == identity else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
    }
  }

  public func metadata(
    for url: URL,
    expectedIdentity: DeletionFileIdentity? = nil
  ) throws -> FileMetadata {
    let initialIdentity = try identity(for: url)
    if let expectedIdentity, expectedIdentity != initialIdentity {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
    }
    let values = try url.resourceValues(forKeys: [
      .fileSizeKey,
      .fileAllocatedSizeKey,
      .totalFileAllocatedSizeKey,
      .fileResourceIdentifierKey,
      .creationDateKey,
      .contentModificationDateKey,
      .isSymbolicLinkKey,
    ])

    let logicalSize = Int64(values.fileSize ?? 0)
    let allocatedSize = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    let physicalIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }

    let metadata = FileMetadata(
      logicalByteCount: logicalSize,
      allocatedByteCount: allocatedSize,
      physicalIdentifier: physicalIdentifier,
      creationDate: values.creationDate,
      modificationDate: values.contentModificationDate,
      isSymbolicLink: values.isSymbolicLink ?? false
    )
    guard try identity(for: url) == initialIdentity else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
    }
    return metadata
  }

  public func readData(
    from url: URL,
    maximumByteCount: Int,
    expectedIdentity: DeletionFileIdentity? = nil
  ) throws -> Data {
    let initialIdentity = try identity(for: url)
    let handle = try openReadOnlyHandle(
      from: url,
      expectedIdentity: expectedIdentity ?? initialIdentity
    )
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumByteCount) ?? Data()
    guard try identity(for: url) == initialIdentity else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
    }
    return data
  }

  func openReadOnlyHandle(
    from url: URL,
    expectedIdentity: DeletionFileIdentity? = nil
  ) throws -> FileHandle {
    let initialIdentity = try identity(for: url)
    if let expectedIdentity, expectedIdentity != initialIdentity {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
    }
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    var descriptorInformation = stat()
    guard fstat(descriptor, &descriptorInformation) == 0 else {
      close(descriptor)
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let openedIdentity = DeletionFileIdentity(
      deviceID: UInt64(descriptorInformation.st_dev),
      fileID: UInt64(descriptorInformation.st_ino),
      mode: UInt32(descriptorInformation.st_mode),
      byteCount: Int64(descriptorInformation.st_size),
      modificationSeconds: Int64(descriptorInformation.st_mtimespec.tv_sec),
      modificationNanoseconds: Int64(descriptorInformation.st_mtimespec.tv_nsec)
    )
    guard openedIdentity == initialIdentity else {
      close(descriptor)
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(EAGAIN))
    }
    return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
  }
}
