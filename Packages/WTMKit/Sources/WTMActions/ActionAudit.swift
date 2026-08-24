import Foundation
import WTMDomain

public struct ActionAuditEntry: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let occurredAt: Date
  public let action: String
  public let providerIDs: [ProviderID]
  public let operationCount: Int
  public let succeededCount: Int
  public let failedCount: Int
  public let status: DeletionExecutionStatus
  public let includedIrreversibleOperation: Bool

  public init(
    id: UUID = UUID(),
    occurredAt: Date,
    action: String = "delete",
    providerIDs: [ProviderID],
    operationCount: Int,
    succeededCount: Int,
    failedCount: Int,
    status: DeletionExecutionStatus,
    includedIrreversibleOperation: Bool
  ) {
    self.id = id
    self.occurredAt = occurredAt
    self.action = action
    self.providerIDs = providerIDs.sorted { $0.rawValue < $1.rawValue }
    self.operationCount = max(operationCount, 0)
    self.succeededCount = max(succeededCount, 0)
    self.failedCount = max(failedCount, 0)
    self.status = status
    self.includedIrreversibleOperation = includedIrreversibleOperation
  }
}

public protocol ActionAuditStoring: Sendable {
  func entries() async throws -> [ActionAuditEntry]
  func append(_ entry: ActionAuditEntry) async throws
  func clear() async throws
}

public actor InMemoryActionAuditStore: ActionAuditStoring {
  private var storedEntries: [ActionAuditEntry]

  public init(entries: [ActionAuditEntry] = []) {
    storedEntries = entries
  }

  public func entries() -> [ActionAuditEntry] { storedEntries }

  public func append(_ entry: ActionAuditEntry) {
    storedEntries.append(entry)
  }

  public func clear() {
    storedEntries = []
  }
}
