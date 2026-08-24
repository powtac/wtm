import SwiftUI

struct SourceSetupView: View {
  @Bindable var model: InventoryViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("source.setup.title")
          .font(.title2.bold())
        Text("source.setup.description")
          .foregroundStyle(.secondary)
      }

      List {
        ForEach(model.sources) { source in
          Toggle(
            isOn: Binding(
              get: { source.isEnabled },
              set: { model.setSourceEnabled(source.id, enabled: $0) }
            )
          ) {
            VStack(alignment: .leading) {
              Text(source.displayName)
              Text(source.rootURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .frame(minHeight: 180)

      HStack {
        Button("source.add-folder.action") {
          model.addManualFolder()
        }
        Spacer()
        Button("source.scan-enabled.action") {
          model.startScan()
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.sources.allSatisfy { !$0.isEnabled })
      }
    }
    .padding(28)
  }
}
