import AppKit

@MainActor
final class WTMApplicationDelegate: NSObject, NSApplicationDelegate {
  var prepareForTermination: (@escaping @MainActor () -> Void) -> Void = { completion in
    completion()
  }
  private var terminationIsInProgress = false
  private var menuBarController: MacMenuBarController?

  func configureMenuBar(model: InventoryViewModel, openInventory: @escaping @MainActor () -> Void) {
    guard menuBarController == nil else { return }
    menuBarController = MacMenuBarController(model: model, openInventory: openInventory)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationIsInProgress else { return .terminateNow }
    terminationIsInProgress = true
    prepareForTermination {
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
