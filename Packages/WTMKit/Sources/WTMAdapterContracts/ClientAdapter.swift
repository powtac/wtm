import WTMDomain

public enum ClientAdapterError: Error, Equatable, Sendable {
  case unsupportedInstallation
  case toolNotInstalled
  case verifiedRuntimeRequired
  case invalidEndpoint
  case invalidTool
}

/// Reviewed client knowledge without process or application-opening authority.
public protocol ClientAdapter: Sendable {
  var id: ClientAdapterID { get }
  var displayName: String { get }
  var version: String { get }

  func availability(
    for installation: ModelInstallation,
    context: ClientHandoffContext
  ) -> ClientAvailability

  func makeHandoffPlan(
    for installation: ModelInstallation,
    context: ClientHandoffContext
  ) throws -> ClientHandoffPlan
}
