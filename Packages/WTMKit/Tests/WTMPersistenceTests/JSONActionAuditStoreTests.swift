import Foundation
import Testing
import WTMActions
import WTMDomain
import WTMPersistence

@Test("Action audit is bounded, secrets-free, and clearable")
func actionAuditIsBoundedAndClearable() async throws {
  let directoryURL = FileManager.default.temporaryDirectory.appending(
    path: "wtm-audit-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
  defer { try? FileManager.default.removeItem(at: directoryURL) }
  let auditURL = directoryURL.appending(path: "action-audit.json")
  let store = JSONActionAuditStore(auditURL: auditURL, maximumEntryCount: 2)
  for index in 0..<3 {
    try await store.append(
      ActionAuditEntry(
        occurredAt: Date(timeIntervalSince1970: Double(index)),
        providerIDs: [.manual],
        operationCount: 1,
        succeededCount: 1,
        failedCount: 0,
        status: .succeeded,
        includedIrreversibleOperation: false
      )
    )
  }

  let entries = try await store.entries()
  #expect(entries.count == 2)
  #expect(
    entries.map(\.occurredAt) == [
      Date(timeIntervalSince1970: 2), Date(timeIntervalSince1970: 1),
    ])
  let payload = try String(contentsOf: auditURL, encoding: .utf8)
  #expect(!payload.contains("/Users/"))
  #expect(!payload.contains("model"))
  #expect(!payload.contains("token"))

  try await store.clear()
  #expect(try await store.entries().isEmpty)
}
