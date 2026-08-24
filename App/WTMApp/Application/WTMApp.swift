import SwiftUI

@main
struct WTMApp: App {
  @State private var model = AppComposition.makeInventoryViewModel()

  var body: some Scene {
    WindowGroup {
      InventoryRootView(model: model)
        .frame(minWidth: 920, minHeight: 600)
    }
    .defaultSize(width: 1_180, height: 760)

    Settings {
      SettingsRootView(model: model)
        .frame(width: 620, height: 440)
    }
  }
}
