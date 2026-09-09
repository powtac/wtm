import Foundation
import WTMDomain

public struct LocalModelConnectionPolicy: Sendable {
  public init() {}

  public func validate(_ connection: LocalModelConnection) throws {
    try LoopbackEndpointPolicy().validate(connection.endpoint)
    guard ["", "/"].contains(connection.endpoint.path),
      !connection.modelReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      connection.modelReference.utf8.count <= 512,
      !connection.modelReference.contains(","),
      connection.modelReference.rangeOfCharacter(from: .controlCharacters) == nil
    else { throw LoopbackEndpointPolicyError.invalidURL }
  }
}
