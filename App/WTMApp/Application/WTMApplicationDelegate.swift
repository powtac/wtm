import AppKit

@MainActor
final class WTMApplicationDelegate: NSObject, NSApplicationDelegate {
  var prepareForTermination: (@escaping @MainActor () -> Void) -> Void = { completion in
    completion()
  }
  private var terminationIsInProgress = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !terminationIsInProgress else { return .terminateLater }
    terminationIsInProgress = true
    prepareForTermination {
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}
