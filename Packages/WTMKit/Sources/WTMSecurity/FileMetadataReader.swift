import Foundation

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

  public func metadata(for url: URL) throws -> FileMetadata {
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

    return FileMetadata(
      logicalByteCount: logicalSize,
      allocatedByteCount: allocatedSize,
      physicalIdentifier: physicalIdentifier,
      creationDate: values.creationDate,
      modificationDate: values.contentModificationDate,
      isSymbolicLink: values.isSymbolicLink ?? false
    )
  }

  public func readData(from url: URL, maximumByteCount: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    return try handle.read(upToCount: maximumByteCount) ?? Data()
  }
}
