import Foundation
import WTMDomain
import WTMRuntime

struct RuntimeReadinessKey: Hashable {
  let installationID: ModelInstallation.ID
  let adapterID: RuntimeAdapterID
}

struct RuntimeToolTemplate: Identifiable {
  var id: RuntimeAdapterID { runtimeAdapterID }

  let runtimeAdapterID: RuntimeAdapterID
  let displayName: String
  let defaultDefinition: ToolDefinition?
  let makeDefinition: (URL) -> ToolDefinition
}

struct RuntimePlanPreview: Identifiable {
  var id: RuntimeTestPlan.ID { plan.id }

  let installation: ModelInstallation
  let runtimeName: String
  let plan: RuntimeTestPlan
  let validation: ToolValidationRecord?
  let approvalToPersist: ToolExecutionApproval?

  var requiresApproval: Bool { approvalToPersist != nil }
}

enum RuntimeUIError: String, Identifiable {
  case runtimeUnavailable
  case toolDisabled
  case toolInvalid
  case executableChanged
  case planFailed
  case launchFailed
  case stopFailed
  case settingsFailed

  var id: String { rawValue }

  var message: String {
    switch self {
    case .runtimeUnavailable: String(localized: "runtime.error.unavailable")
    case .toolDisabled: String(localized: "runtime.error.tool-disabled")
    case .toolInvalid: String(localized: "runtime.error.tool-invalid")
    case .executableChanged: String(localized: "runtime.error.executable-changed")
    case .planFailed: String(localized: "runtime.error.plan-failed")
    case .launchFailed: String(localized: "runtime.error.launch-failed")
    case .stopFailed: String(localized: "runtime.error.stop-failed")
    case .settingsFailed: String(localized: "runtime.error.settings-failed")
    }
  }
}

extension RuntimeAdapterID {
  var localizedName: String {
    switch self {
    case .ollama: "Ollama"
    case .llamaCpp: "llama.cpp"
    default: rawValue
    }
  }
}

extension ToolDefinitionOrigin {
  var displayName: String {
    switch self {
    case .builtIn: String(localized: "tool.origin.built-in")
    case .userCreated: String(localized: "tool.origin.user-override")
    case .imported: String(localized: "tool.origin.imported")
    }
  }
}
