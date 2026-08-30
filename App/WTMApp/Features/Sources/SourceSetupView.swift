import SwiftUI

struct SourceSetupView: View {
  @Bindable var model: InventoryViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text("source.setup.title")
          .font(.title2.bold())
          .accessibilityAddTraits(.isHeader)
        Text("source.setup.description")
        Label("source.setup.no-media-access", systemImage: "mic.slash")
          .font(.callout)
          .padding(.top, 6)
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
              Text(source.accessState.localizedName)
                .font(.caption)
            }
          }
          .accessibilityIdentifier("source-toggle-\(source.id)")
          .accessibilityLabel(Text(source.displayName))
          .accessibilityValue(
            Text(
              verbatim:
                "\(source.accessState.localizedName), \(source.isEnabled ? "Enabled" : "Disabled")"
            )
          )
          .accessibilityHint(Text("accessibility.source.toggle.hint"))
        }
      }
      .frame(minHeight: 180)
      .accessibilityLabel(Text("accessibility.source.list.label"))

      HStack {
        Button("source.add-folder.action") {
          model.addManualFolder()
        }
        Button("source.add-mlx-folder.action") {
          model.addMLXFolder()
        }
        Spacer()
        Button("source.scan-enabled.action") {
          model.completeOnboardingAndStartScan()
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.sources.allSatisfy { !$0.isEnabled })
        .accessibilityHint(Text("accessibility.scan.hint"))
      }
    }
    .padding(28)
  }
}
