import Foundation
import WTMDomain

public struct LlamaCppToolConvention: Sendable {
  public static let definitionID = UUID(
    uuid: (
      0x77, 0x74, 0x6D, 0x00, 0x6C, 0x6C, 0x61, 0x6D,
      0x61, 0x63, 0x70, 0x70, 0x00, 0x00, 0x00, 0x01
    )
  )

  public init() {}

  public func discoveredDefinition(
    fileManager: FileManager = .default
  ) -> ToolDefinition? {
    let home = fileManager.homeDirectoryForCurrentUser
    let candidates = [
      URL(filePath: "/opt/homebrew/bin/llama-server"),
      URL(filePath: "/usr/local/bin/llama-server"),
      home.appending(path: ".local/bin/llama-server"),
    ]
    guard
      let executableURL = candidates.first(where: { candidate in
        fileManager.isExecutableFile(atPath: candidate.path)
      })
    else { return nil }
    return definition(executableURL: executableURL, origin: .builtIn)
  }

  public func definition(
    executableURL: URL,
    origin: ToolDefinitionOrigin,
    isEnabled: Bool = false
  ) -> ToolDefinition {
    ToolDefinition(
      id: Self.definitionID,
      displayName: "llama.cpp Server",
      role: .runtime,
      runtimeAdapterID: .llamaCpp,
      origin: .builtIn,
      isEnabled: isEnabled,
      executableURL: executableURL,
      arguments: [
        .literal("--model"), .placeholder(.modelPath),
        .literal("--host"), .literal("127.0.0.1"),
        .literal("--port"), .placeholder(.port),
      ],
      supportedFormats: [.gguf]
    )
  }
}
