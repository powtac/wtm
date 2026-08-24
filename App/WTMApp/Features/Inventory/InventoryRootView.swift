import SwiftUI
import WTMDomain

struct InventoryRootView: View {
  @Bindable var model: InventoryViewModel
  @AppStorage("inventory.storage-display-mode") private var storageDisplayModeRaw =
    StorageDisplayMode.absolute.rawValue
  @AppStorage("inventory.table-columns") private var columnCustomization =
    TableColumnCustomization<InventoryTableRow>()
  @State private var sortOrder = [
    KeyPathComparator(\InventoryTableRow.sortName, order: .forward)
  ]

  @ViewBuilder
  var body: some View {
    if model.isPreparingSources {
      ProgressView("source.loading")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if !model.hasCompletedOnboarding {
      SourceSetupView(model: model)
        .frame(minWidth: 720, minHeight: 480)
    } else {
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

      if model.selectedSection == .issues {
        issueContent
      } else if model.visibleInstallations.isEmpty {
        VStack(spacing: 16) {
          ContentUnavailableView(
            model.isScanning ? "scan.status.title" : "inventory.empty.title",
            systemImage: model.isScanning
              ? "magnifyingglass"
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
        let rows = inventoryTableRows(
          installations: model.visibleInstallations,
          mode: storageDisplayMode,
          breakdown: model.storageBreakdown
        )
        let allRows = inventoryTableRows(
          installations: model.installations,
          mode: storageDisplayMode,
          breakdown: model.storageBreakdown
        )
        let sourceNames = Dictionary(
          uniqueKeysWithValues: model.sources.map { ($0.id, $0.displayName) }
        )
        let columnWidths = inventoryTableColumnWidths(
          rows: allRows,
          mode: storageDisplayMode,
          totalByteCount: model.storageBreakdown.totalByteCount,
          sourceName: { sourceNames[$0] ?? $0 }
        )

        Table(
          rows.sorted(using: sortOrder),
          selection: $model.selectedInstallationID,
          sortOrder: $sortOrder,
          columnCustomization: $columnCustomization
        ) {
          TableColumn("inventory.column.name", value: \.sortName) { row in
            let installation = row.installation
            Text(installation.identity.displayName)
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.name,
            max: .infinity
          )
          .customizationID("name")
          TableColumn("inventory.column.provider", value: \.sortProvider) { row in
            Text(row.installation.providerID.localizedName)
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.provider,
            max: .infinity
          )
          .customizationID("provider")
          TableColumn("inventory.column.format", value: \.sortFormat) { row in
            Text(formatAndQuantizationText(row.installation))
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.format,
            max: .infinity
          )
          .customizationID("format")
          TableColumn("inventory.column.state", value: \.sortState) { row in
            Text(row.installation.state.localizedName)
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.state,
            max: .infinity
          )
          .customizationID("state")
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
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.size,
            max: .infinity
          )
          .customizationID("size")
          TableColumn("inventory.column.reclaimable", value: \.sortReclaimableSize) { row in
            Text(wholeByteCount(row.reclaimableByteCount))
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.reclaimableSize,
            max: .infinity
          )
          .customizationID("reclaimable")
          TableColumn("inventory.column.age", value: \.sortAge) { row in
            Text(installationAgeText(row.installation))
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.age,
            max: .infinity
          )
          .customizationID("age")
          TableColumn("inventory.column.date", value: \.sortDate) { row in
            Text(firstChangeText(row.installation))
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.date,
            max: .infinity
          )
          .customizationID("date")
          .defaultVisibility(.hidden)
          TableColumn("inventory.column.source", value: \.sortSource) { row in
            Text(sourceName(for: row.installation.sourceID))
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.source,
            max: .infinity
          )
          .customizationID("source")
          .defaultVisibility(.hidden)
          TableColumn("inventory.column.path", value: \.sortPath) { row in
            Text(row.installation.rootURL.path)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          .width(
            min: InventoryTableColumnWidths.minimum,
            ideal: columnWidths.path,
            max: .infinity
          )
          .customizationID("path")
        }
      }
    }
  }

  @ViewBuilder
  private var issueContent: some View {
    if model.issues.isEmpty {
      ContentUnavailableView(
        "issues.empty.title",
        systemImage: "checkmark.shield",
        description: Text("issues.empty.description")
      )
    } else {
      List(model.issues) { issue in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(issue.localizedSummary)
            Spacer()
            Text(issue.code)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }
          if let affectedURL = issue.affectedURL {
            Text(affectedURL.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        .accessibilityElement(children: .combine)
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

      Menu {
        Picker("filter.provider", selection: $model.selectedProviderID) {
          Text("filter.any-provider").tag(nil as ProviderID?)
          ForEach(model.filterProviderIDs, id: \.self) { providerID in
            Text(providerID.localizedName).tag(providerID as ProviderID?)
          }
        }
        Picker("filter.format", selection: $model.selectedFormat) {
          Text("filter.any-format").tag(nil as ModelFormat?)
          ForEach(model.filterFormats, id: \.self) { format in
            Text(format.localizedName).tag(format as ModelFormat?)
          }
        }
        Picker("filter.state", selection: $model.selectedState) {
          Text("filter.any-state").tag(nil as InstallationState?)
          ForEach(model.filterStates, id: \.self) { state in
            Text(state.localizedName).tag(state as InstallationState?)
          }
        }
        Picker("filter.source", selection: $model.selectedSourceID) {
          Text("filter.any-source").tag(nil as ScanSource.ID?)
          ForEach(model.filterSources) { source in
            Text(source.displayName).tag(source.id as ScanSource.ID?)
          }
        }
        Divider()
        Button("filter.clear") {
          model.clearInventoryFilters()
        }
        .disabled(!model.hasActiveInventoryFilter)
      } label: {
        Label("filter.action", systemImage: "line.3.horizontal.decrease.circle")
      }
      .disabled(model.installations.isEmpty)
    }
  }

  private func sourceName(for sourceID: ScanSource.ID) -> String {
    model.sources.first(where: { $0.id == sourceID })?.displayName ?? sourceID
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
