import AppKit
import SwiftUI

@main
struct WTMApp: App {
  @Environment(\.openWindow) private var openWindow
  @NSApplicationDelegateAdaptor(WTMApplicationDelegate.self) private var applicationDelegate
  @State private var model = AppComposition.makeInventoryViewModel()
  @State private var updateChecker = UpdateChecker()

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
          if ProcessInfo.processInfo.environment["WTM_DISABLE_AUTOMATIC_UPDATE_CHECK"] != "1" {
            await updateChecker.checkAutomaticallyIfDue()
          }
          if ProcessInfo.processInfo.environment["WTM_UI_TEST_SHOW_ABOUT"] == "1" {
            openWindow(id: "about")
          }
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
    .commands {
      CommandGroup(replacing: .appInfo) {
        Button("app.about.action") {
          openWindow(id: "about")
        }
        Button("update.check.action") {
          updateChecker.checkManually()
        }
      }
    }

    Settings {
      SettingsRootView(model: model, updateChecker: updateChecker)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 600)
    }

    Window("app.about.window", id: "about") {
      AboutView(checker: updateChecker)
    }
    .defaultSize(width: 560, height: 520)
    .windowResizability(.contentSize)
  }

}
