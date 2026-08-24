import Foundation
import WTMDomain

/// Built-in source suggestions. Suggestions are deliberately disabled until the user approves them.
public struct DefaultSourceCatalog: Sendable {
  public init() {}

  public func suggestions(homeDirectory: URL) -> [ScanSource] {
    [
      ScanSource(
        id: "default:ollama",
        displayName: "Ollama",
        providerID: .ollama,
        rootURL: homeDirectory.appending(path: ".ollama/models", directoryHint: .isDirectory)
      ),
      ScanSource(
        id: "default:hugging-face",
        displayName: "Hugging Face",
        providerID: .huggingFace,
        rootURL: homeDirectory.appending(
          path: ".cache/huggingface/hub",
          directoryHint: .isDirectory
        )
      ),
    ]
  }
}
