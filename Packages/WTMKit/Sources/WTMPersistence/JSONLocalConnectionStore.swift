import Foundation
import WTMDomain

/// Synchronous snapshots for adapters, serialized atomic writes for explicit user edits.
public final class JSONLocalConnectionStore: @unchecked Sendable {
  private struct Payload: Codable {
    var schemaVersion = 1
    var services: [String: [String: LocalModelConnection]] = [:]
  }
  private let lock = NSLock()
  private let url: URL?
  private var payload: Payload

  public init(url: URL? = nil) throws {
    self.url = url
    if let url, FileManager.default.fileExists(atPath: url.path) {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 1_048_577) ?? Data()
      guard data.count <= 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
      payload = try JSONDecoder().decode(Payload.self, from: data)
      guard payload.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
    } else {
      payload = Payload()
    }
  }

  public func connection(serviceID: String, installationID: String) -> LocalModelConnection? {
    lock.withLock { payload.services[serviceID]?[installationID] }
  }

  public func removeAll() throws {
    try lock.withLock {
      let empty = Payload()
      if let url {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(empty).write(to: url, options: .atomic)
      }
      payload = empty
    }
  }

  public func set(_ value: LocalModelConnection?, serviceID: String, installationID: String) throws
  {
    try lock.withLock {
      var updated = payload
      updated.services[serviceID, default: [:]][installationID] = value
      let data = try JSONEncoder().encode(updated)
      guard data.count <= 1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
      if let url {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
      }
      payload = updated
    }
  }
}
