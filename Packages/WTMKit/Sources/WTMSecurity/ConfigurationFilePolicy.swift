import Foundation

/// Filename-only policy used before any model configuration content can be considered for reading.
public struct ConfigurationFilePolicy: Sendable {
  private let allowedNames: Set<String> = [
    ".metadata.json",
    "adapter_config.json",
    "config.json",
    "generation_config.json",
    "model.safetensors.index.json",
    "preprocessor_config.json",
    "processor_config.json",
    "special_tokens_map.json",
    "tokenizer_config.json",
  ]

  public init() {}

  public func isAllowed(_ url: URL) -> Bool {
    allowedNames.contains(url.lastPathComponent.lowercased()) && !isSecretSuspect(url)
  }

  public func isSecretSuspect(_ url: URL) -> Bool {
    let name = url.lastPathComponent.lowercased()
    if [
      ".env",
      ".netrc",
      "credentials",
      "credentials.json",
      "id_dsa",
      "id_ecdsa",
      "id_ed25519",
      "id_rsa",
    ].contains(name) {
      return true
    }
    if [".pem", ".key", ".p12", ".pfx"].contains(where: name.hasSuffix) { return true }
    return name.contains("private_key") || name.contains("access_token")
      || name.contains("api_key")
  }
}
