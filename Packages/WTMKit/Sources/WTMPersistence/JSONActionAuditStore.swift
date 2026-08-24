import Foundation
import WTMActions

public actor JSONActionAuditStore: ActionAuditStoring {
  private struct Payload: Codable {
    static let currentVersion = 1

    let version: Int
    let entries: [ActionAuditEntry]
  }

  private let auditURL: URL
  private let maximumEntryCount: Int

  public init(auditURL: URL, maximumEntryCount: Int = 500) {
    self.auditURL = auditURL
    self.maximumEntryCount = max(maximumEntryCount, 1)
  }

  public func entries() throws -> [ActionAuditEntry] {
    guard FileManager.default.fileExists(atPath: auditURL.path) else { return [] }
    let data = try Data(contentsOf: auditURL, options: [.mappedIfSafe])
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    guard payload.version == Payload.currentVersion else { return [] }
    return payload.entries.sorted { $0.occurredAt > $1.occurredAt }
  }

  public func append(_ entry: ActionAuditEntry) throws {
    var updated = try entries()
    updated.insert(entry, at: 0)
    if updated.count > maximumEntryCount {
      updated.removeLast(updated.count - maximumEntryCount)
    }
    try save(updated)
  }

  public func clear() throws {
    try save([])
  }

  private func save(_ entries: [ActionAuditEntry]) throws {
    let payload = Payload(version: Payload.currentVersion, entries: entries)
    let data = try JSONEncoder().encode(payload)
    try FileManager.default.createDirectory(
      at: auditURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: auditURL, options: [.atomic])
  }
}
