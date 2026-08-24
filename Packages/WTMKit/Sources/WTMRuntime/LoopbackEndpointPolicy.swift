import Foundation

public enum LoopbackEndpointPolicyError: Error, Equatable, Sendable {
  case invalidURL
  case unsupportedScheme
  case credentialsForbidden
  case nonLoopbackHost
  case missingPort
  case queryOrFragmentForbidden
}

public struct LoopbackEndpointPolicy: Sendable {
  public init() {}

  public func validate(_ url: URL) throws {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.host != nil
    else {
      throw LoopbackEndpointPolicyError.invalidURL
    }
    guard components.scheme?.lowercased() == "http" else {
      throw LoopbackEndpointPolicyError.unsupportedScheme
    }
    guard components.user == nil, components.password == nil else {
      throw LoopbackEndpointPolicyError.credentialsForbidden
    }
    guard let host = components.host?.lowercased(), Self.loopbackHosts.contains(host) else {
      throw LoopbackEndpointPolicyError.nonLoopbackHost
    }
    guard let port = components.port, (1...65_535).contains(port) else {
      throw LoopbackEndpointPolicyError.missingPort
    }
    guard components.query == nil, components.fragment == nil else {
      throw LoopbackEndpointPolicyError.queryOrFragmentForbidden
    }
  }

  private static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "[::1]"]
}
