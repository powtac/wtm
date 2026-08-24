import Foundation
import WTMDomain

extension ProviderID {
  var localizedName: String {
    switch self {
    case .ollama: String(localized: "provider.ollama")
    case .huggingFace: String(localized: "provider.hugging-face")
    case .manual: String(localized: "provider.manual")
    default: rawValue
    }
  }
}

extension ModelFormat {
  var localizedName: String {
    switch self {
    case .gguf: String(localized: "format.gguf")
    case .safetensors: String(localized: "format.safetensors")
    case .mlx: String(localized: "format.mlx")
    case .ollama: String(localized: "format.ollama")
    case .unknown: String(localized: "format.unknown")
    }
  }
}

extension InstallationState {
  var localizedName: String {
    switch self {
    case .stored: String(localized: "installation-state.stored")
    case .incomplete: String(localized: "installation-state.incomplete")
    case .issue: String(localized: "installation-state.issue")
    case .offline: String(localized: "installation-state.offline")
    }
  }
}
