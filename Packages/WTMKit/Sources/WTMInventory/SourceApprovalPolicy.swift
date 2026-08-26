import Foundation
import WTMDomain
import WTMSecurity

/// Creates the consent-bound source capability consumed by scans and cleanup.
public struct SourceApprovalPolicy: Sendable {
  public init() {}

  public func approve(_ source: ScanSource) throws -> ScanSource {
    let identity = try SourceRootPolicy().capture(
      rootURL: source.rootURL,
      volumeIdentity: source.volumeIdentity
    )
    return ScanSource(
      id: source.id,
      displayName: source.displayName,
      providerID: source.providerID,
      rootURL: source.rootURL,
      volumeIdentity: source.volumeIdentity,
      rootIdentity: identity,
      accessState: .allowed,
      isEnabled: true
    )
  }

  public func revalidate(_ source: ScanSource) throws {
    guard let identity = source.rootIdentity else {
      throw ScopedPathError.sourceIdentityUnavailable
    }
    try SourceRootPolicy().revalidate(
      rootURL: source.rootURL,
      volumeIdentity: source.volumeIdentity,
      expected: identity
    )
  }
}
