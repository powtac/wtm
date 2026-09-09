import Foundation

/// Stable identifier for a storage provider without closing the adapter ecosystem to an enum.
public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue }
}

extension ProviderID {
  public static let ollama = ProviderID(rawValue: "ollama")
  public static let huggingFace = ProviderID(rawValue: "hugging-face")
  public static let mlx = ProviderID(rawValue: "mlx")
  public static let gpt4All = ProviderID(rawValue: "gpt4all")
  public static let jan = ProviderID(rawValue: "jan")
  public static let lmStudio = ProviderID(rawValue: "lm-studio")
  public static let manual = ProviderID(rawValue: "manual")
}
