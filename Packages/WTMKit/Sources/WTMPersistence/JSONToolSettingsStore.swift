import Foundation
import WTMDomain

public struct ToolSettingsSnapshot: Hashable, Codable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let revision: UInt64
  public let definitions: [ToolDefinition]
  public let approvals: [ToolExecutionApproval]

  public init(
    schemaVersion: Int = ToolSettingsSnapshot.currentSchemaVersion,
    revision: UInt64,
    definitions: [ToolDefinition],
    approvals: [ToolExecutionApproval]
  ) {
    self.schemaVersion = schemaVersion
    self.revision = revision
    self.definitions = definitions.sorted { $0.id.uuidString < $1.id.uuidString }
    self.approvals = approvals.sorted { $0.definitionID.uuidString < $1.definitionID.uuidString }
  }
}

public protocol ToolSettingsStoring: Sendable {
  func load() async throws -> ToolSettingsSnapshot?
  func save(_ snapshot: ToolSettingsSnapshot) async throws
}

public actor JSONToolSettingsStore: ToolSettingsStoring {
  private let settingsURL: URL
  private var highestSavedRevision: UInt64 = 0

  public init(settingsURL: URL) {
    self.settingsURL = settingsURL
  }

  public func load() throws -> ToolSettingsSnapshot? {
    guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
    let data = try Data(contentsOf: settingsURL, options: [.mappedIfSafe])
    let snapshot = try JSONDecoder().decode(ToolSettingsSnapshot.self, from: data)
    guard snapshot.schemaVersion == ToolSettingsSnapshot.currentSchemaVersion else { return nil }
    highestSavedRevision = snapshot.revision
    return snapshot
  }

  public func save(_ snapshot: ToolSettingsSnapshot) throws {
    guard snapshot.revision >= highestSavedRevision else { return }
    guard snapshot.schemaVersion == ToolSettingsSnapshot.currentSchemaVersion else { return }
    try FileManager.default.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(snapshot).write(to: settingsURL, options: [.atomic])
    highestSavedRevision = snapshot.revision
  }
}
