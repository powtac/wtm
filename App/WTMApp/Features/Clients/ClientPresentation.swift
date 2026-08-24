import WTMDomain

struct ClientPlanPreview: Identifiable {
  var id: ClientHandoffPlan.ID { plan.id }
  let installation: ModelInstallation
  let clientName: String
  let plan: ClientHandoffPlan
}

enum ClientUIError: Error {
  case unavailable
  case planFailed
  case launchFailed

  var message: String {
    switch self {
    case .unavailable: String(localized: "client.error.unavailable")
    case .planFailed: String(localized: "client.error.plan-failed")
    case .launchFailed: String(localized: "client.error.launch-failed")
    }
  }
}
