import Foundation

/// Explicit user mapping to an already-running local service; contains no credentials.
public struct LocalModelConnection: Hashable, Codable, Sendable {
  public let endpoint: URL
  public let modelReference: String

  public init(endpoint: URL, modelReference: String) {
    self.endpoint = endpoint
    self.modelReference = modelReference
  }
}
