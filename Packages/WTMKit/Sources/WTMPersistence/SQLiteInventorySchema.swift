import Foundation
import SQLite3

public enum PersistenceError: Error, Equatable, Sendable {
  case openFailed(String)
  case migrationFailed(String)
  case queryFailed(String)
}

/// Owns the normalized, regenerable SQLite index schema for Phase 1.
public actor SQLiteInventorySchema {
  private let databaseAddress: UInt

  public init(databaseURL: URL) throws {
    var openedDatabase: OpaquePointer?
    let result = sqlite3_open_v2(
      databaseURL.path,
      &openedDatabase,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard result == SQLITE_OK, let openedDatabase else {
      let message = openedDatabase.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
      sqlite3_close(openedDatabase)
      throw PersistenceError.openFailed(message)
    }
    databaseAddress = UInt(bitPattern: openedDatabase)

    do {
      try Self.migrate(database: openedDatabase)
    } catch {
      sqlite3_close(openedDatabase)
      throw error
    }
  }

  deinit {
    sqlite3_close(OpaquePointer(bitPattern: databaseAddress))
  }

  public func tableNames() throws -> [String] {
    guard let database = OpaquePointer(bitPattern: databaseAddress) else {
      throw PersistenceError.queryFailed("Database connection is unavailable")
    }
    let query = "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
      throw PersistenceError.queryFailed(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }

    var names: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let text = sqlite3_column_text(statement, 0) else { continue }
      names.append(String(cString: text))
    }
    return names
  }

  private static func migrate(database: OpaquePointer) throws {
    let statements = [
      "PRAGMA journal_mode = WAL;",
      "PRAGMA foreign_keys = ON;",
      """
      CREATE TABLE IF NOT EXISTS scan_source (
        id TEXT PRIMARY KEY,
        provider_id TEXT NOT NULL,
        root_path TEXT NOT NULL,
        volume_identifier TEXT,
        last_scan_at REAL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS model_identity (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        family TEXT
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS model_variant (
        id TEXT PRIMARY KEY,
        identity_id TEXT NOT NULL REFERENCES model_identity(id),
        format TEXT NOT NULL,
        quantization TEXT
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS model_installation (
        id TEXT PRIMARY KEY,
        variant_id TEXT NOT NULL REFERENCES model_variant(id),
        source_id TEXT NOT NULL REFERENCES scan_source(id),
        provider_id TEXT NOT NULL,
        root_path TEXT NOT NULL,
        state TEXT NOT NULL
      );
      """,
      """
      CREATE TABLE IF NOT EXISTS artifact (
        id TEXT PRIMARY KEY,
        installation_id TEXT NOT NULL REFERENCES model_installation(id),
        path TEXT NOT NULL,
        kind TEXT NOT NULL,
        logical_bytes INTEGER NOT NULL,
        allocated_bytes INTEGER NOT NULL,
        physical_identifier TEXT,
        is_shared INTEGER NOT NULL,
        is_partial INTEGER NOT NULL
      );
      """,
      "CREATE INDEX IF NOT EXISTS artifact_physical_id ON artifact(physical_identifier);",
    ]

    for statement in statements {
      var errorMessage: UnsafeMutablePointer<CChar>?
      guard sqlite3_exec(database, statement, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "Unknown migration error"
        sqlite3_free(errorMessage)
        throw PersistenceError.migrationFailed(message)
      }
    }
  }
}
