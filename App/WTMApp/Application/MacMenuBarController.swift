import AppKit
import WTMDomain
import WTMInventory

struct MenuBarInventorySummary: Equatable {
  let modelCount: Int
  let totalByteCount: Int64
  let oldModelCount: Int
  let incompleteByteCount: Int64
  let issueCount: Int
  let runningModelCount: Int
  let offlineSourceCount: Int
}

func menuBarInventorySummary(
  installations: [ModelInstallation],
  totalByteCount: Int64,
  issueCount: Int,
  runningModelCount: Int,
  sources: [ScanSource],
  oldModelThresholdDays: Int,
  now: Date
) -> MenuBarInventorySummary {
  MenuBarInventorySummary(
    modelCount: installations.count,
    totalByteCount: totalByteCount,
    oldModelCount: installations.count { installation in
      guard let date = installation.earliestChangeTimestamp?.value else { return false }
      return now.timeIntervalSince(date) >= Double(oldModelThresholdDays) * 86_400
    },
    incompleteByteCount: InventoryStorageBreakdown(
      installations: installations.filter { $0.state == .incomplete }
    ).totalByteCount,
    issueCount: issueCount,
    runningModelCount: runningModelCount,
    offlineSourceCount: sources.count { $0.isEnabled && $0.accessState == .offline }
  )
}

@MainActor
final class MacMenuBarController: NSObject, NSMenuDelegate {
  private let model: InventoryViewModel
  private let openInventory: @MainActor () -> Void
  private var statusItem: NSStatusItem?

  init(model: InventoryViewModel, openInventory: @escaping @MainActor () -> Void) {
    self.model = model
    self.openInventory = openInventory
    super.init()

    guard ProcessInfo.processInfo.environment["XCTestBundlePath"] == nil else { return }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(defaultsDidChange(_:)),
      name: UserDefaults.didChangeNotification,
      object: UserDefaults.standard
    )
    applyEnabledSetting()
  }

  func menuWillOpen(_ menu: NSMenu) {
    rebuild(menu)
  }

  private func applyEnabledSetting() {
    let storedValue = UserDefaults.standard.object(forKey: "menu-bar.enabled") as? Bool
    let isEnabled = storedValue ?? true

    if isEnabled, statusItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
      item.button?.image = NSImage(
        systemSymbolName: "externaldrive.badge.checkmark",
        accessibilityDescription: String(localized: "app.name")
      )
      let menu = NSMenu()
      menu.delegate = self
      item.menu = menu
      statusItem = item
    } else if !isEnabled, let statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
      self.statusItem = nil
    }
  }

  @objc private func defaultsDidChange(_: Notification) {
    applyEnabledSetting()
  }

  private func rebuild(_ menu: NSMenu) {
    let summary = menuBarInventorySummary(
      installations: model.installations,
      totalByteCount: model.storageBreakdown.totalByteCount,
      issueCount: model.issues.count,
      runningModelCount: model.runtimeSessions.values.count { $0.instance.state == .running },
      sources: model.sources,
      oldModelThresholdDays: model.oldModelThresholdDays,
      now: .now
    )
    menu.removeAllItems()
    menu.addItem(informationalItem(title: String(localized: "app.name"), isHeader: true))
    menu.addItem(.separator())
    menu.addItem(
      informationalItem(title: "\(String(localized: "menu.models")): \(summary.modelCount)"))
    menu.addItem(
      informationalItem(
        title:
          "\(String(localized: "menu.storage")): \(wholeByteCount(summary.totalByteCount))"
      )
    )
    menu.addItem(
      informationalItem(title: "\(String(localized: "menu.old")): \(summary.oldModelCount)"))
    menu.addItem(
      informationalItem(
        title:
          "\(String(localized: "menu.incomplete")): \(wholeByteCount(summary.incompleteByteCount))"
      )
    )
    menu.addItem(
      contextItem(
        title: "\(String(localized: "menu.issues")): \(summary.issueCount)",
        count: summary.issueCount,
        action: #selector(showIssues)
      )
    )
    menu.addItem(
      contextItem(
        title: "\(String(localized: "menu.running")): \(summary.runningModelCount)",
        count: summary.runningModelCount,
        action: #selector(showRunningModels)
      )
    )
    menu.addItem(
      informationalItem(
        title: "\(String(localized: "menu.offline-sources")): \(summary.offlineSourceCount)"
      )
    )

    if let path = model.compactCurrentScanPath {
      menu.addItem(.separator())
      menu.addItem(informationalItem(title: path))
    } else if let lastScanDate = model.lastScanDate {
      let relativeDate = RelativeDateTimeFormatter().localizedString(
        for: lastScanDate,
        relativeTo: .now
      )
      menu.addItem(.separator())
      menu.addItem(
        informationalItem(title: "\(String(localized: "menu.last-scan")): \(relativeDate)")
      )
    } else {
      menu.addItem(.separator())
      menu.addItem(informationalItem(title: String(localized: "menu.not-scanned")))
    }

    menu.addItem(.separator())
    menu.addItem(
      actionItem(title: String(localized: "menu.open"), action: #selector(showInventory)))
    menu.addItem(
      actionItem(
        title: String(localized: model.isScanning ? "scan.cancel.action" : "scan.action"),
        action: #selector(toggleScan)
      )
    )
  }

  private func informationalItem(title: String, isHeader: Bool = false) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    if isHeader {
      item.attributedTitle = NSAttributedString(
        string: title,
        attributes: [.font: NSFont.menuFont(ofSize: 0).withWeight(.semibold)]
      )
    }
    return item
  }

  private func actionItem(title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func contextItem(title: String, count: Int, action: Selector) -> NSMenuItem {
    count > 0 ? actionItem(title: title, action: action) : informationalItem(title: title)
  }

  @objc private func showInventory() {
    openInventory()
  }

  @objc private func showIssues() {
    model.selectedInstallationIDs.removeAll()
    model.selectedSection = .issues
    openInventory()
  }

  @objc private func showRunningModels() {
    model.selectedSection = .all
    model.selectedInstallationIDs = Set(
      model.runtimeSessions.values
        .filter { $0.instance.state == .running }
        .map(\.instance.installationID)
    )
    openInventory()
  }

  @objc private func toggleScan() {
    model.isScanning ? model.cancelScan() : model.startScan()
  }
}

private extension NSFont {
  func withWeight(_ weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: pointSize, weight: weight)
  }
}
