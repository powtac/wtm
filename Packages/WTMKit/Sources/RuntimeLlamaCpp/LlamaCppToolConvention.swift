import Foundation
import WTMDomain

public struct LlamaCppToolConvention: Sendable {
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
    return ToolDefinition(
      id: UUID(),
      displayName: "llama.cpp Server",
      role: .runtime,
      origin: .builtIn,
      isEnabled: false,
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
