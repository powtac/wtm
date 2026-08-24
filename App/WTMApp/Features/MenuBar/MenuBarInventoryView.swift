import AppKit
import SwiftUI
import WTMDomain

struct MenuBarInventoryView: View {
  @Environment(\.openWindow) private var openWindow
  @Bindable var model: InventoryViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(
          "app.name",
          systemImage: model.isScanning
            ? "arrow.triangle.2.circlepath" : "externaldrive.badge.checkmark"
        )
        .font(.headline)
        Spacer()
        if model.isScanning {
          ProgressView()
            .controlSize(.small)
        }
      }

      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
        metric("menu.models", value: "\(model.installations.count)")
        metric("menu.storage", value: wholeByteCount(model.storageBreakdown.totalByteCount))
        metric("menu.old", value: "\(oldModelCount)")
        metric("menu.incomplete", value: "\(incompleteModelCount)")
        metric("menu.issues", value: "\(model.issues.count)")
        metric("menu.running", value: "\(runningModelCount)")
        metric("menu.offline-sources", value: "\(offlineSourceCount)")
      }

      if let path = model.compactCurrentScanPath {
        Label(path, systemImage: "folder")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      } else if let lastScanDate = model.lastScanDate {
        LabeledContent("menu.last-scan") {
          Text(lastScanDate, format: .relative(presentation: .named))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Text("menu.not-scanned")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Divider()

      HStack {
        Button("menu.open") {
          openInventory()
        }
        Button(model.isScanning ? "scan.cancel.action" : "scan.action") {
          model.isScanning ? model.cancelScan() : model.startScan()
        }
        .keyboardShortcut("r", modifiers: .command)
      }
    }
    .padding(14)
    .frame(width: 300)
  }

  private func metric(_ key: LocalizedStringKey, value: String) -> some View {
    GridRow {
      Text(key)
        .foregroundStyle(.secondary)
      Text(value)
        .monospacedDigit()
        .gridColumnAlignment(.trailing)
    }
  }

  private var oldModelCount: Int {
    model.installations.filter { installation in
      guard let date = installation.earliestChangeTimestamp?.value else { return false }
      return Date.now.timeIntervalSince(date) >= Double(model.oldModelThresholdDays) * 86_400
    }.count
  }

  private var incompleteModelCount: Int {
    model.installations.count { $0.state == .incomplete }
  }

  private var runningModelCount: Int {
    model.runtimeSessions.values.count { $0.instance.state == .running }
  }

  private var offlineSourceCount: Int {
    model.sources.count { $0.isEnabled && $0.accessState == .offline }
  }

  private func openInventory() {
    openWindow(id: "inventory")
    NSApplication.shared.activate(ignoringOtherApps: true)
  }
}
