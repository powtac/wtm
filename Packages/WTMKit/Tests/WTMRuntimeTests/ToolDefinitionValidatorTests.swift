import Foundation
import Testing
import WTMDomain

@testable import WTMRuntime

private func definition(
  origin: ToolDefinitionOrigin = .userCreated,
  isEnabled: Bool = false,
  executableURL: URL = URL(filePath: "/usr/bin/true"),
  arguments: [ToolArgument] = [.literal("--model"), .placeholder(.modelPath)],
  endpoint: URL? = nil,
  environment: [String: String] = [:]
) -> ToolDefinition {
  ToolDefinition(
    id: UUID(),
    displayName: "Runtime",
    role: .runtime,
    origin: origin,
    isEnabled: isEnabled,
    executableURL: executableURL,
    arguments: arguments,
    supportedFormats: [.gguf],
    localAPIBaseURL: endpoint,
    environment: environment
  )
}

@Test("Imported definitions cannot arrive enabled")
func importedDefinitionsDefaultToDisabled() {
  #expect(throws: ToolDefinitionValidationError.importedDefinitionMustBeDisabled) {
    try ToolDefinitionValidator().validate(definition(origin: .imported, isEnabled: true))
  }
}

@Test("Runtime endpoint policy rejects remote and hostname endpoints")
func endpointPolicyRequiresNumericLoopback() {
  let policy = LoopbackEndpointPolicy()

  #expect(throws: LoopbackEndpointPolicyError.nonLoopbackHost) {
    try policy.validate(URL(string: "http://example.com:11434")!)
  }
  #expect(throws: LoopbackEndpointPolicyError.nonLoopbackHost) {
    try policy.validate(URL(string: "http://localhost:11434")!)
  }
  #expect(throws: Never.self) {
    try policy.validate(URL(string: "http://127.0.0.1:11434")!)
  }
}

@Test("Environment rejects search paths and dynamic-loader injection")
func environmentUsesClosedAllowlist() {
  for key in ["PATH", "HOME", "DYLD_INSERT_LIBRARIES"] {
    #expect(throws: ToolDefinitionValidationError.disallowedEnvironmentKey(key)) {
      try ToolDefinitionValidator().validate(definition(environment: [key: "/tmp/value"]))
    }
  }
}

@Test("Typed placeholder values stay a single argv element")
func argumentValuesAreNeverParsedAsShell() throws {
  let enabledDefinition = definition(isEnabled: true)
  let builder = ToolInvocationBuilder()
  let validation = try builder.inspect(enabledDefinition)
  let approval = ToolExecutionApproval(
    definitionID: enabledDefinition.id,
    executableIdentity: validation.executableIdentity,
    approvedAt: .now
  )
  let hostilePath = "/tmp/model.gguf; rm -rf /"

  let invocation = try builder.makeInvocation(
    definition: enabledDefinition,
    values: RuntimeArgumentValues(modelPath: hostilePath),
    modelFormat: .gguf,
    approval: approval
  )

  #expect(invocation.arguments == ["--model", hostilePath])
  #expect(invocation.executableURL == URL(filePath: "/usr/bin/true"))
}

@Test("Approval is bound to one tool definition")
func approvalCannotCrossDefinitions() throws {
  let first = definition(isEnabled: true)
  let second = definition(isEnabled: true)
  let builder = ToolInvocationBuilder()
  let validation = try builder.inspect(first)
  let approval = ToolExecutionApproval(
    definitionID: first.id,
    executableIdentity: validation.executableIdentity,
    approvedAt: .now
  )

  #expect(throws: ToolInvocationBuilderError.executableNotApproved) {
    _ = try builder.makeInvocation(
      definition: second,
      values: RuntimeArgumentValues(modelPath: "/tmp/model.gguf"),
      modelFormat: .gguf,
      approval: approval
    )
  }
}

@Test("Changing an approved executable symlink invalidates execution")
func executableSymlinkChangesRequireNewApproval() throws {
  let fileManager = FileManager.default
  let directory = fileManager.temporaryDirectory.appending(
    path: "wtm-runtime-symlink-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
  try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? fileManager.removeItem(at: directory) }

  let link = directory.appending(path: "runtime")
  try fileManager.createSymbolicLink(at: link, withDestinationURL: URL(filePath: "/usr/bin/true"))
  let enabledDefinition = definition(isEnabled: true, executableURL: link)
  let builder = ToolInvocationBuilder()
  let validation = try builder.inspect(enabledDefinition)
  let approval = ToolExecutionApproval(
    definitionID: enabledDefinition.id,
    executableIdentity: validation.executableIdentity,
    approvedAt: .now
  )

  try fileManager.removeItem(at: link)
  try fileManager.createSymbolicLink(at: link, withDestinationURL: URL(filePath: "/usr/bin/false"))

  #expect(throws: ToolInvocationBuilderError.executableIdentityChanged) {
    _ = try builder.makeInvocation(
      definition: enabledDefinition,
      values: RuntimeArgumentValues(modelPath: "/tmp/model.gguf"),
      modelFormat: .gguf,
      approval: approval
    )
  }
}
