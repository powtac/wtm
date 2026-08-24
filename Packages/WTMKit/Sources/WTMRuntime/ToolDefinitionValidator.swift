import Foundation
import WTMDomain

public enum ToolDefinitionValidationError: Error, Equatable, Sendable {
  case unsupportedSchema(Int)
  case emptyDisplayName
  case unsupportedRole
  case importedDefinitionMustBeDisabled
  case invalidExecutableURL
  case emptySupportedFormats
  case tooManyArguments
  case argumentTooLong
  case invalidArgument
  case disallowedEnvironmentKey(String)
  case invalidEnvironmentValue(String)
  case invalidCurrentDirectory
  case invalidEndpoint(LoopbackEndpointPolicyError)
}

public struct ToolDefinitionValidator: Sendable {
  public static let allowedEnvironmentKeys: Set<String> = [
    "GGML_METAL_PATH_RESOURCES", "LANG", "LC_ALL", "TMPDIR",
  ]

  private let endpointPolicy: LoopbackEndpointPolicy

  public init(endpointPolicy: LoopbackEndpointPolicy = LoopbackEndpointPolicy()) {
    self.endpointPolicy = endpointPolicy
  }

  public func validate(_ definition: ToolDefinition, forExecution: Bool = false) throws {
    guard definition.schemaVersion == ToolDefinition.currentSchemaVersion else {
      throw ToolDefinitionValidationError.unsupportedSchema(definition.schemaVersion)
    }
    guard !definition.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ToolDefinitionValidationError.emptyDisplayName
    }
    if forExecution, definition.role != .runtime {
      throw ToolDefinitionValidationError.unsupportedRole
    }
    if definition.origin == .imported, definition.isEnabled {
      throw ToolDefinitionValidationError.importedDefinitionMustBeDisabled
    }
    guard definition.executableURL.isFileURL,
      definition.executableURL.path.hasPrefix("/"),
      !definition.executableURL.path.contains("\0")
    else {
      throw ToolDefinitionValidationError.invalidExecutableURL
    }
    guard !definition.supportedFormats.isEmpty else {
      throw ToolDefinitionValidationError.emptySupportedFormats
    }
    guard definition.arguments.count <= 128 else {
      throw ToolDefinitionValidationError.tooManyArguments
    }
    for argument in definition.arguments {
      guard case .literal(let value) = argument else { continue }
      guard value.utf8.count <= 4_096 else {
        throw ToolDefinitionValidationError.argumentTooLong
      }
      guard !value.contains("\0") else {
        throw ToolDefinitionValidationError.invalidArgument
      }
    }
    for (key, value) in definition.environment {
      guard Self.allowedEnvironmentKeys.contains(key) else {
        throw ToolDefinitionValidationError.disallowedEnvironmentKey(key)
      }
      guard !value.contains("\0"), value.utf8.count <= 4_096 else {
        throw ToolDefinitionValidationError.invalidEnvironmentValue(key)
      }
    }
    if let currentDirectoryURL = definition.currentDirectoryURL {
      guard currentDirectoryURL.isFileURL,
        currentDirectoryURL.path.hasPrefix("/"),
        !currentDirectoryURL.path.contains("\0")
      else {
        throw ToolDefinitionValidationError.invalidCurrentDirectory
      }
    }
    if let endpoint = definition.localAPIBaseURL {
      do {
        try endpointPolicy.validate(endpoint)
      } catch let error as LoopbackEndpointPolicyError {
        throw ToolDefinitionValidationError.invalidEndpoint(error)
      }
    }
  }
}
