import SwiftUI
import WTMDomain

struct InventoryRootView: View {
  @Bindable var model: InventoryViewModel
  @AppStorage("inventory.storage-display-mode") private var storageDisplayModeRaw =
    StorageDisplayMode.absolute.rawValue
  @State private var sortOrder = [
    KeyPathComparator(\InventoryTableRow.sortName, order: .forward)
  ]

  var body: some View {
    NavigationSplitView {
      List(InventorySection.allCases, selection: $model.selectedSection) { section in
        Label(String(localized: section.localizedKey), systemImage: section.systemImage)
          .tag(section)
      }
      .navigationTitle(Text("app.name"))
    } content: {
      inventoryContent
        .navigationTitle(Text("inventory.title"))
        .searchable(text: $model.searchText, prompt: Text("inventory.search.prompt"))
        .toolbar { inventoryToolbar }
    } detail: {
      InstallationDetailView(
        installation: model.selectedInstallation,
        revealAction: model.reveal
      )
    }
  }

  @ViewBuilder
  private var inventoryContent: some View {
    VStack(spacing: 0) {
      if let activeScan = model.activeScan {
        activeScanStatus(activeScan)
        Divider()
      } else if let summary = model.scanSummary {
        scanCompletionStatus(summary)
        Divider()
      }

      if model.hasCompletedOnboarding, !model.installations.isEmpty {
        storageControls
        Divider()
      }

      if model.isPreparingSources {
        ProgressView("source.loading")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if !model.hasCompletedOnboarding {
        SourceSetupView(model: model)
      } else if model.visibleInstallations.isEmpty {
        VStack(spacing: 16) {
          ContentUnavailableView(
            model.isScanning ? "scan.status.title" : "inventory.empty.title",
            systemImage: model.isScanning
              ? "externaldrive.badge.magnifyingglass"
              : "externaldrive.badge.questionmark",
            description: Text(
              model.isScanning ? "scan.status.empty-description" : "inventory.empty.description"
            )
          )
          if !model.isScanning {
            Button("scan.action") {
              model.startScan()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.sources.allSatisfy { !$0.isEnabled })
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Table(
          inventoryTableRows(
            installations: model.visibleInstallations,
            mode: storageDisplayMode,
            breakdown: model.storageBreakdown
          ).sorted(using: sortOrder),
          selection: $model.selectedInstallationID,
          sortOrder: $sortOrder
        ) {
          TableColumn("inventory.column.name", value: \.sortName) { row in
            let installation = row.installation
            Text(installation.identity.displayName)
          }
          TableColumn("inventory.column.provider", value: \.sortProvider) { row in
            Text(row.installation.providerID.localizedName)
          }
          TableColumn("inventory.column.format", value: \.sortFormat) { row in
            Text(row.installation.variant.format.localizedName)
          }
          TableColumn("inventory.column.state", value: \.sortState) { row in
            Text(row.installation.state.localizedName)
          }
          TableColumn(storageColumnTitle, value: \.sortSize) { row in
            if storageDisplayMode == .absolute {
              Text(wholeByteCount(row.displayedByteCount))
            } else {
              Text(
                percentageText(
                  row.displayedByteCount,
                  of: model.storageBreakdown.totalByteCount
                )
              )
            }
          }
          TableColumn("inventory.column.age", value: \.sortAge) { row in
            Text(installationAgeText(row.installation))
          }
          TableColumn("inventory.column.path", value: \.sortPath) { row in
            Text(row.installation.rootURL.path)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
      }
    }
  }

  private var storageDisplayMode: StorageDisplayMode {
    StorageDisplayMode(rawValue: storageDisplayModeRaw) ?? .absolute
  }

  private var storageColumnTitle: String {
    switch storageDisplayMode {
    case .absolute: String(localized: "inventory.column.size")
    case .share: String(localized: "inventory.column.share")
    }
  }

  private var storageControls: some View {
    let breakdown = model.storageBreakdown
    return HStack(spacing: 10) {
      Picker("storage.mode.label", selection: $storageDisplayModeRaw) {
        Text("storage.mode.absolute").tag(StorageDisplayMode.absolute.rawValue)
        Text("storage.mode.share").tag(StorageDisplayMode.share.rawValue)
      }
      .pickerStyle(.segmented)
      .fixedSize()

      if storageDisplayMode == .share {
        Text("storage.shared")
          .foregroundStyle(.secondary)
        Text(percentageText(breakdown.sharedByteCount, of: breakdown.totalByteCount))
          .monospacedDigit()
        Text("storage.unknown")
          .foregroundStyle(.secondary)
        Text(percentageText(breakdown.unknownByteCount, of: breakdown.totalByteCount))
          .monospacedDigit()
      }
      Spacer()
      Text(wholeByteCount(breakdown.totalByteCount))
        .monospacedDigit()
      Text("storage.active-scope")
        .foregroundStyle(.secondary)
    }
    .font(.callout)
    .padding(.horizontal, 14)
    .padding(.vertical, 7)
    .help("storage.share.help")
  }

  @ToolbarContentBuilder
  private var inventoryToolbar: some ToolbarContent {
    ToolbarItemGroup {
      Button {
        model.startScan()
      } label: {
        Label(
          model.lastScanDate == nil ? "scan.action" : "scan.rescan.action",
          systemImage: "arrow.clockwise"
        )
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut("r", modifiers: [.command])
      .disabled(
        model.isPreparingSources || !model.hasCompletedOnboarding || model.isScanning
          || model.sources.allSatisfy { !$0.isEnabled }
      )

      if model.isScanning {
        Button(role: .cancel) {
          model.cancelScan()
        } label: {
          Label("scan.cancel.action", systemImage: "stop.circle")
        }
      }
    }
  }

  private func activeScanStatus(_ state: ActiveScanState) -> some View {
    HStack(spacing: 12) {
      ProgressView()
        .controlSize(.small)
      VStack(alignment: .leading, spacing: 2) {
        Text("scan.status.title")
          .font(.headline)
        if let source = state.currentSource, let path = model.compactCurrentScanPath {
          Text("\(source.displayName) · \(path)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(source.rootURL.path)
        }
      }
      Spacer()
      Text("\(state.discoveredInstallationCount)")
        .monospacedDigit()
      Text("scan.status.found")
        .foregroundStyle(.secondary)
      Text("\(state.completedSourceCount)/\(state.totalSourceCount)")
        .monospacedDigit()
        .foregroundStyle(.secondary)
      Text(state.startedAt, style: .time)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .accessibilityElement(children: .combine)
  }

  private func scanCompletionStatus(_ summary: ScanCompletionSummary) -> some View {
    HStack(spacing: 8) {
      Image(systemName: summary.wasCancelled ? "stop.circle" : "checkmark.circle")
      Text(summary.wasCancelled ? "scan.summary.cancelled" : "scan.summary.completed")
      Text("\(summary.scannedSourceCount)")
        .monospacedDigit()
      Text("scan.summary.sources")
      Spacer()
      Text("\(summary.installationCount)")
        .monospacedDigit()
      Text("scan.status.found")
      Text("·")
      Text(wholeByteCount(summary.allocatedByteCount))
        .monospacedDigit()
      Text("scan.summary.total")
        .foregroundStyle(.secondary)
      Text("·")
      Text("\(summary.issueCount)")
        .monospacedDigit()
      Text("scan.summary.issues")
      Text(summary.completedAt, style: .time)
        .foregroundStyle(.secondary)
    }
    .font(.callout)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
  }

}
