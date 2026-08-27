import Foundation

public struct GGUFInspection: Hashable, Sendable {
  public let version: UInt32
  public let tensorCount: UInt64
  public let architecture: String?
  public let name: String?
  public let huggingFaceRepositoryID: String?

  public var containsModelWeights: Bool { tensorCount > 0 }

  public init(
    version: UInt32,
    tensorCount: UInt64,
    architecture: String?,
    name: String?,
    huggingFaceRepositoryID: String?
  ) {
    self.version = version
    self.tensorCount = tensorCount
    self.architecture = architecture
    self.name = name
    self.huggingFaceRepositoryID = huggingFaceRepositoryID
  }
}

public enum GGUFHeaderReaderError: Error, Equatable, Sendable {
  case invalidMagic
  case unsupportedVersion(UInt32)
  case truncated
  case malformed
  case headerTooLarge
}

/// Bounded, read-only inspection of GGUF headers. It never reads tensor data.
public struct GGUFHeaderReader: Sendable {
  public static let defaultMaximumReadByteCount = 64 * 1_024 * 1_024

  private let maximumReadByteCount: Int
  private let maximumMetadataEntries = 1_000_000
  private let maximumArrayElements = 4_000_000
  private let maximumStringByteCount = 4 * 1_024 * 1_024

  public init(maximumReadByteCount: Int = GGUFHeaderReader.defaultMaximumReadByteCount) {
    self.maximumReadByteCount = max(maximumReadByteCount, 24)
  }

  public func inspect(at url: URL) throws -> GGUFInspection {
    let data: Data
    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      data = try handle.read(upToCount: maximumReadByteCount) ?? Data()
    } catch {
      throw GGUFHeaderReaderError.truncated
    }

    var cursor = DataCursor(data: data)
    guard try cursor.readData(count: 4) == Data("GGUF".utf8) else {
      throw GGUFHeaderReaderError.invalidMagic
    }
    let version = try cursor.readUInt32()
    guard version == 2 || version == 3 else {
      throw GGUFHeaderReaderError.unsupportedVersion(version)
    }
    let tensorCount = try cursor.readUInt64()
    let metadataCount = try cursor.readUInt64()
    guard metadataCount <= UInt64(maximumMetadataEntries) else {
      throw GGUFHeaderReaderError.malformed
    }

    var architecture: String?
    var name: String?
    var sourceRepository: String?
    for _ in 0..<Int(metadataCount) {
      let key = try cursor.readString(maximumByteCount: maximumStringByteCount)
      let type = try cursor.readUInt32()
      let stringValue: String?
      if type == GGUFValueType.string.rawValue {
        stringValue = try cursor.readString(maximumByteCount: maximumStringByteCount)
      } else {
        stringValue = nil
        try cursor.skipValue(type: type, maximumArrayElements: maximumArrayElements)
      }

      switch key {
      case "general.architecture": architecture = stringValue
      case "general.name": name = stringValue
      case "general.repo_url", "general.source_repo_url":
        if let stringValue, let repositoryID = Self.huggingFaceRepositoryID(from: stringValue) {
          sourceRepository = repositoryID
        }
      default: break
      }
    }

    return GGUFInspection(
      version: version,
      tensorCount: tensorCount,
      architecture: architecture,
      name: name,
      huggingFaceRepositoryID: sourceRepository
    )
  }

  private static func huggingFaceRepositoryID(from value: String) -> String? {
    guard let components = URLComponents(string: value),
      components.scheme?.lowercased() == "https",
      components.host?.lowercased() == "huggingface.co",
      components.port == nil,
      components.query == nil,
      components.fragment == nil
    else { return nil }

    let path = components.path.split(separator: "/", omittingEmptySubsequences: true)
    guard path.count == 2 else { return nil }
    let repository = path.map(String.init)
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    guard repository.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) })
    else { return nil }
    return repository.joined(separator: "/")
  }
}

private enum GGUFValueType: UInt32 {
  case uint8 = 0
  case int8 = 1
  case uint16 = 2
  case int16 = 3
  case uint32 = 4
  case int32 = 5
  case float32 = 6
  case bool = 7
  case string = 8
  case array = 9
  case uint64 = 10
  case int64 = 11
  case float64 = 12
}

private struct DataCursor {
  let data: Data
  var offset = 0

  mutating func readData(count: Int) throws -> Data {
    guard count >= 0, offset <= data.count, count <= data.count - offset else {
      throw GGUFHeaderReaderError.truncated
    }
    defer { offset += count }
    return data.subdata(in: offset..<(offset + count))
  }

  mutating func readUInt32() throws -> UInt32 {
    let bytes = try [UInt8](readData(count: 4))
    return UInt32(bytes[0])
      | (UInt32(bytes[1]) << 8)
      | (UInt32(bytes[2]) << 16)
      | (UInt32(bytes[3]) << 24)
  }

  mutating func readUInt64() throws -> UInt64 {
    let bytes = try [UInt8](readData(count: 8))
    return bytes.enumerated().reduce(UInt64(0)) { result, item in
      result | (UInt64(item.element) << (UInt64(item.offset) * 8))
    }
  }

  mutating func readString(maximumByteCount: Int) throws -> String {
    let count = try readUInt64()
    guard count <= UInt64(maximumByteCount), count <= UInt64(Int.max) else {
      throw GGUFHeaderReaderError.malformed
    }
    guard let string = String(data: try readData(count: Int(count)), encoding: .utf8) else {
      throw GGUFHeaderReaderError.malformed
    }
    return string
  }

  mutating func skipValue(type: UInt32, maximumArrayElements: Int) throws {
    guard let valueType = GGUFValueType(rawValue: type) else {
      throw GGUFHeaderReaderError.malformed
    }
    switch valueType {
    case .uint8, .int8, .bool: _ = try readData(count: 1)
    case .uint16, .int16: _ = try readData(count: 2)
    case .uint32, .int32, .float32: _ = try readData(count: 4)
    case .uint64, .int64, .float64: _ = try readData(count: 8)
    case .string: _ = try readString(maximumByteCount: 4 * 1_024 * 1_024)
    case .array:
      let elementType = try readUInt32()
      let count = try readUInt64()
      guard count <= UInt64(maximumArrayElements) else {
        throw GGUFHeaderReaderError.headerTooLarge
      }
      for _ in 0..<Int(count) {
        try skipValue(type: elementType, maximumArrayElements: maximumArrayElements)
      }
    }
  }
}
