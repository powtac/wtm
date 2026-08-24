import Foundation
import WTMDomain
import WTMRuntime

struct RuntimeReadinessKey: Hashable {
  let installationID: ModelInstallation.ID
  let adapterID: RuntimeAdapterID
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

  var messageKey: String.LocalizationValue {
    switch self {
    case .runtimeUnavailable: "runtime.error.unavailable"
    case .toolDisabled: "runtime.error.tool-disabled"
    case .toolInvalid: "runtime.error.tool-invalid"
    case .executableChanged: "runtime.error.executable-changed"
    case .planFailed: "runtime.error.plan-failed"
    case .launchFailed: "runtime.error.launch-failed"
    case .stopFailed: "runtime.error.stop-failed"
    case .settingsFailed: "runtime.error.settings-failed"
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
