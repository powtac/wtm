import SwiftUI
import WTMDomain

struct InventoryRootView: View {
  @Bindable var model: InventoryViewModel

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
      InstallationDetailView(installation: model.selectedInstallation)
    }
  }

  @ViewBuilder
  private var inventoryContent: some View {
    if model.sources.allSatisfy({ !$0.isEnabled }) {
      SourceSetupView(model: model)
    } else if model.visibleInstallations.isEmpty, !model.isScanning {
      ContentUnavailableView(
        "inventory.empty.title",
        systemImage: "externaldrive.badge.questionmark",
        description: Text("inventory.empty.description")
      )
    } else {
      Table(model.visibleInstallations, selection: $model.selectedInstallationID) {
        TableColumn("inventory.column.name") { installation in
          Text(installation.identity.displayName)
        }
        TableColumn("inventory.column.provider") { installation in
          Text(installation.providerID.localizedName)
        }
        TableColumn("inventory.column.format") { installation in
          Text(installation.variant.format.localizedName)
        }
        TableColumn("inventory.column.state") { installation in
          Text(installation.state.localizedName)
        }
        TableColumn("inventory.column.size") { installation in
          Text(byteCount(installation.allocatedByteCount))
        }
        TableColumn("inventory.column.path") { installation in
          Text(installation.rootURL.path)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
  }

  @ToolbarContentBuilder
  private var inventoryToolbar: some ToolbarContent {
    ToolbarItemGroup {
      Button {
        model.revealSelectedInstallation()
      } label: {
        Label("inventory.reveal.action", systemImage: "folder")
      }
      .disabled(model.selectedInstallation == nil)

      if model.isScanning {
        Button(role: .cancel) {
          model.cancelScan()
        } label: {
          Label("scan.cancel.action", systemImage: "stop.circle")
        }
      } else {
        Button {
          model.startScan()
        } label: {
          Label("scan.action", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: [.command])
      }
    }
  }

  private func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
  }
}
