import SwiftUI
import WTMDomain

struct ClientSectionView: View {
  @Bindable var model: InventoryViewModel
  let installation: ModelInstallation

  var body: some View {
    let clientIDs = model.clientOptions(for: installation)
    if !clientIDs.isEmpty {
      Section("client.section") {
        ForEach(clientIDs, id: \.rawValue) { clientID in
          ClientAdapterRowView(
            model: model,
            installation: installation,
            clientID: clientID
          )
        }
      }
    }
  }
}

private struct ClientAdapterRowView: View {
  @Bindable var model: InventoryViewModel
  let installation: ModelInstallation
  let clientID: ClientAdapterID

  var body: some View {
    let availability = model.clientAvailability(clientID, for: installation)
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(clientID.displayName)
        Spacer()
        Button("client.prepare.action") {
          model.prepareClientHandoff(clientID, for: installation)
        }
        .disabled(!availability.isAvailable)
      }
      Text(availability.summary)
        .font(.caption)
        .foregroundStyle(availability.isAvailable ? Color.secondary : Color.orange)
    }
  }
}

extension ClientAdapterID {
  var displayName: String {
    switch self {
    case .openClaw: "OpenClaw"
    case .unsloth: "Unsloth Studio"
    default: rawValue
    }
  }
}

extension ClientAvailability {
  var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }

  var summary: String {
    switch self {
    case .available(let summary), .unavailable(let summary): summary
    }
  }
}
