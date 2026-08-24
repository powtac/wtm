import Foundation

public enum IssueSeverity: String, Codable, CaseIterable, Sendable {
  case info
  case warning
  case error
  case blocking
}

public struct InventoryIssue: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let code: String
  public let severity: IssueSeverity
  public let sourceID: ScanSource.ID
  public let summary: String
  public let affectedURL: URL?
  public let occurredAt: Date

  public init(
    id: String,
    code: String,
    severity: IssueSeverity,
    sourceID: ScanSource.ID,
    summary: String,
    affectedURL: URL? = nil,
    occurredAt: Date = .now
  ) {
    self.id = id
    self.code = code
    self.severity = severity
    self.sourceID = sourceID
    self.summary = summary
    self.affectedURL = affectedURL
    self.occurredAt = occurredAt
  }
}
