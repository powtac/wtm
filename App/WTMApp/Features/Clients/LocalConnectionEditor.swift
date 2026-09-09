import SwiftUI
import WTMDomain

struct LocalConnectionEditor: View {
  @Bindable var model: InventoryViewModel
  let serviceID: String
  let installationID: String
  @State private var endpoint = ""
  @State private var reference = ""
  @State private var failed = false
  @State private var saved = false

  var body: some View {
    DisclosureGroup("connection.configure") {
      Text("connection.explanation")
        .font(.caption)
      TextField("connection.endpoint", text: $endpoint)
      TextField("connection.model", text: $reference)
      HStack {
        Button("connection.save") { save() }
        Button("connection.disconnect") {
          do {
            try model.saveLocalConnection(nil, serviceID: serviceID, installationID: installationID)
            saved = false
            failed = false
          } catch { failed = true }
        }
      }
      if failed { Text("connection.error").foregroundStyle(.orange) }
      if saved { Text("connection.saved").foregroundStyle(.secondary) }
    }
    .disabled(model.isCheckingRuntime || model.isPreparingRuntime || model.isRunningRuntimeAction)
    .onChange(of: installationID, initial: true) { _, _ in
      endpoint = ""
      reference = ""
      saved = false
      failed = false
      if let config = model.localConnection(serviceID: serviceID, installationID: installationID) {
        endpoint = config.endpoint.absoluteString
        reference = config.modelReference
        saved = true
      }
    }
  }

  private func save() {
    do {
      guard let url = URL(string: endpoint) else { throw ClientUIError.planFailed }
      try model.saveLocalConnection(
        LocalModelConnection(endpoint: url, modelReference: reference),
        serviceID: serviceID, installationID: installationID)
      failed = false
      saved = true
    } catch { failed = true; saved = false }
  }
}
