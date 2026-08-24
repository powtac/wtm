import SwiftUI

struct SettingsRootView: View {
  @Bindable var model: InventoryViewModel

  var body: some View {
    TabView {
      Form {
        Section("settings.sources.section") {
          ForEach(model.sources) { source in
            Toggle(
              source.displayName,
              isOn: Binding(
                get: { source.isEnabled },
                set: { model.setSourceEnabled(source.id, enabled: $0) }
              )
            )
          }
          Button("source.add-folder.action") {
            model.addManualFolder()
          }
        }
      }
      .tabItem { Label("settings.sources", systemImage: "externaldrive") }

      Form {
        Section("settings.security.section") {
          Text("settings.security.description")
          if let adapterGuideURL = URL(
            string: "https://github.com/powtac/wtm/blob/main/docs/adapters.md"
          ) {
            Link("settings.extend.action", destination: adapterGuideURL)
          }
        }
      }
      .tabItem { Label("settings.security", systemImage: "lock.shield") }
    }
    .padding()
  }
}
