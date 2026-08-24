import Foundation
import WTMDomain

/// Built-in source suggestions. Suggestions are deliberately disabled until the user approves them.
public struct DefaultSourceCatalog: Sendable {
  public static let version = 2

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
      ScanSource(
        id: "default:unsloth",
        displayName: "Unsloth",
        providerID: .manual,
        rootURL: homeDirectory.appending(path: ".unsloth", directoryHint: .isDirectory)
      ),
      ScanSource(
        id: "default:models",
        displayName: "Models Folder",
        providerID: .manual,
        rootURL: homeDirectory.appending(path: ".models", directoryHint: .isDirectory)
      ),
    ]
  }
}
