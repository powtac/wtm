import Foundation
import WTMDomain

public struct ToolDefinitionManifest: Hashable, Codable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let definition: ToolDefinition

  public init(
    schemaVersion: Int = ToolDefinitionManifest.currentSchemaVersion,
    definition: ToolDefinition
  ) {
    self.schemaVersion = schemaVersion
    self.definition = definition
  }
}

public enum ToolDefinitionManifestPolicy {
  public static func definitionForImport(
    _ definition: ToolDefinition,
    id: UUID = UUID()
  ) -> ToolDefinition {
    ToolDefinition(
      schemaVersion: definition.schemaVersion,
      id: id,
      displayName: definition.displayName,
      role: definition.role,
      runtimeAdapterID: definition.runtimeAdapterID,
      origin: .imported,
      isEnabled: false,
      executableURL: definition.executableURL,
      arguments: definition.arguments,
      supportedFormats: definition.supportedFormats,
      localAPIBaseURL: definition.localAPIBaseURL,
      currentDirectoryURL: definition.currentDirectoryURL,
      environment: definition.environment
    )
  }

  public static func definitionForExport(
    _ definition: ToolDefinition,
    homeDirectoryURL: URL
  ) -> ToolDefinition {
    let homePath = homeDirectoryURL.standardizedFileURL.path
    func containsHomePath(_ value: String) -> Bool {
      value.contains(homePath)
    }
    let executableURL =
      containsHomePath(definition.executableURL.standardizedFileURL.path)
      ? URL(filePath: "/path/to/\(definition.executableURL.lastPathComponent)")
      : definition.executableURL
    let arguments = definition.arguments.map { argument in
      guard case .literal(let value) = argument, containsHomePath(value) else { return argument }
      return ToolArgument.literal(value.replacingOccurrences(of: homePath, with: "/path/to/home"))
    }
    let environment = definition.environment.filter { !containsHomePath($0.value) }
    return ToolDefinition(
      schemaVersion: definition.schemaVersion,
      id: definition.id,
      displayName: definition.displayName,
      role: definition.role,
      runtimeAdapterID: definition.runtimeAdapterID,
      origin: definition.origin,
      isEnabled: false,
      executableURL: executableURL,
      arguments: arguments,
      supportedFormats: definition.supportedFormats,
      localAPIBaseURL: definition.localAPIBaseURL,
      currentDirectoryURL: definition.currentDirectoryURL.flatMap {
        containsHomePath($0.standardizedFileURL.path) ? nil : $0
      },
      environment: environment
    )
  }
}

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
