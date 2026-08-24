import Foundation
import WTMDomain

public struct RuntimeEnvironment: Hashable, Sendable {
  public let architecture: String
  public let availableMemoryByteCount: Int64?

  public init(architecture: String, availableMemoryByteCount: Int64? = nil) {
    self.architecture = architecture
    self.availableMemoryByteCount = availableMemoryByteCount
  }
}

public struct RuntimeLaunchContext: Hashable, Sendable {
  public let now: Date
  public let port: UInt16?
  public let toolDefinition: ToolDefinition?
  public let toolApproval: ToolExecutionApproval?

  public init(
    now: Date = .now,
    port: UInt16? = nil,
    toolDefinition: ToolDefinition? = nil,
    toolApproval: ToolExecutionApproval? = nil
  ) {
    self.now = now
    self.port = port
    self.toolDefinition = toolDefinition
    self.toolApproval = toolApproval
  }
}

public enum RuntimeAdapterError: Error, Equatable, Sendable {
  case unsupportedFormat(ModelFormat)
  case runtimeNotInstalled
  case invalidToolDefinition
  case executableNotApproved
  case endpointUnavailable
  case providerStopUnsupported
  case providerRequestFailed(String)
}

/// Provider-specific runtime knowledge without process ownership.
///
/// Adapters inspect compatibility, create immutable plans, and verify their own local API.
/// `RuntimeBroker` is the only component allowed to execute or terminate processes.
public protocol RuntimeAdapter: Sendable {
  var id: RuntimeAdapterID { get }
  var displayName: String { get }
  var version: String { get }
  var supportedFormats: Set<ModelFormat> { get }

  func readiness(
    for installation: ModelInstallation,
    environment: RuntimeEnvironment
  ) async -> RuntimeReadiness

  func makeTestPlan(
    for installation: ModelInstallation,
    context: RuntimeLaunchContext
  ) async throws -> RuntimeTestPlan

  func healthCheck(endpoint: URL) async -> RuntimeProbeResult

  func inferenceCheck(
    endpoint: URL,
    installation: ModelInstallation,
    prompt: String
  ) async -> RuntimeProbeResult

  func stopProviderInstance(_ instance: RuntimeInstance) async throws
}

extension RuntimeAdapter {
  public func stopProviderInstance(_ instance: RuntimeInstance) async throws {
    throw RuntimeAdapterError.providerStopUnsupported
  }
}
