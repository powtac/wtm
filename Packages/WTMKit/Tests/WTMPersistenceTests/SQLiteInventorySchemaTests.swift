import Foundation
import Testing

@testable import WTMPersistence

@Test("SQLite migration separates inventory entities")
func migrationCreatesNormalizedTables() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let schema = try SQLiteInventorySchema(databaseURL: directory.appending(path: "inventory.sqlite"))

  let names = try await schema.tableNames()

  #expect(names.contains("scan_source"))
  #expect(names.contains("model_identity"))
  #expect(names.contains("model_variant"))
  #expect(names.contains("model_installation"))
  #expect(names.contains("artifact"))
}
