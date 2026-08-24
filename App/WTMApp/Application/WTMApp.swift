import AppKit
import SwiftUI

@main
struct WTMApp: App {
  @Environment(\.openWindow) private var openWindow
  @NSApplicationDelegateAdaptor(WTMApplicationDelegate.self) private var applicationDelegate
  @State private var model = AppComposition.makeInventoryViewModel()

  var body: some Scene {
    WindowGroup(id: "inventory") {
      InventoryRootView(model: model)
        .frame(minWidth: 920, minHeight: 600)
        .task {
          applicationDelegate.configureMenuBar(model: model) {
            openWindow(id: "inventory")
            NSApplication.shared.activate(ignoringOtherApps: true)
          }
          applicationDelegate.prepareForTermination = { completion in
            Task {
              await model.stopOwnedRuntimeSessionsForTermination()
              completion()
            }
          }
          await model.prepareForLaunch()
        }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)
        ) { _ in
          model.handleVolumeChange()
        }
        .onReceive(
          NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)
        ) { _ in
          model.handleVolumeChange()
        }
    }
    .defaultSize(width: 1_180, height: 760)

    Settings {
      SettingsRootView(model: model)
        .frame(width: 620, height: 440)
    }
  }
}
