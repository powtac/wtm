import Foundation
import WTMDomain

public enum ToolInvocationBuilderError: Error, Equatable, Sendable {
  case definitionDisabled
  case unsupportedModelFormat(ModelFormat)
  case missingPlaceholder(ToolPlaceholder)
  case executableNotApproved
  case executableIdentityChanged
}

public struct ToolInvocationBuilder: Sendable {
  private let validator: ToolDefinitionValidator
  private let inspector: ExecutableInspector

  public init(
    validator: ToolDefinitionValidator = ToolDefinitionValidator(),
    inspector: ExecutableInspector = ExecutableInspector()
  ) {
    self.validator = validator
    self.inspector = inspector
  }

  public func inspect(_ definition: ToolDefinition, checkedAt: Date = .now) throws
    -> ToolValidationRecord
  {
    try validator.validate(definition)
    let inspection = try inspector.inspect(definition.executableURL)
    return ToolValidationRecord(
      checkedAt: checkedAt,
      executableIdentity: inspection.identity,
      signingStatus: inspection.signingStatus,
      signingIdentifier: inspection.signingIdentifier,
      version: inspection.version
    )
  }

  public func makeInvocation(
    definition: ToolDefinition,
    values: RuntimeArgumentValues,
    modelFormat: ModelFormat,
    approval: ToolExecutionApproval
  ) throws -> RuntimeExecutableInvocation {
    try validator.validate(definition, forExecution: true)
    guard definition.isEnabled else {
      throw ToolInvocationBuilderError.definitionDisabled
    }
    guard definition.supportedFormats.contains(modelFormat) else {
      throw ToolInvocationBuilderError.unsupportedModelFormat(modelFormat)
    }
    guard approval.matches(definition) else {
      throw ToolInvocationBuilderError.executableNotApproved
    }

    let inspection = try inspector.inspect(definition.executableURL)
    guard inspection.identity == approval.executableIdentity else {
      throw ToolInvocationBuilderError.executableIdentityChanged
    }

    let arguments = try definition.arguments.map { argument in
      switch argument {
      case .literal(let value): value
      case .placeholder(let placeholder): try resolve(placeholder, from: values)
      }
    }
    return RuntimeExecutableInvocation(
      executableURL: inspection.identity.canonicalURL,
      arguments: arguments,
      currentDirectoryURL: definition.currentDirectoryURL,
      environment: definition.environment,
      approvedIdentity: inspection.identity
    )
  }

  private func resolve(_ placeholder: ToolPlaceholder, from values: RuntimeArgumentValues) throws
    -> String
  {
    let value: String?
    switch placeholder {
    case .modelPath: value = values.modelPath
    case .modelID: value = values.modelID
    case .endpoint: value = values.endpoint
    case .port: value = values.port.map(String.init)
    case .configPath: value = values.configPath
    }
    guard let value else {
      throw ToolInvocationBuilderError.missingPlaceholder(placeholder)
    }
    return value
  }
}
