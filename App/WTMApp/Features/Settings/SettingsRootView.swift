import SwiftUI
import WTMDomain

struct SettingsRootView: View {
  @Bindable var model: InventoryViewModel
  @AppStorage("menu-bar.enabled") private var isMenuBarEnabled = true
  @State private var pendingRevocationSourceID: ScanSource.ID?
  @State private var isAuditClearConfirmationPresented = false

  var body: some View {
    TabView {
      generalSettings
        .tabItem { Label("settings.general", systemImage: "gearshape") }
      sourceSettings
        .tabItem { Label("settings.sources", systemImage: "externaldrive") }
      integrationSettings
        .tabItem { Label("settings.integrations", systemImage: "puzzlepiece.extension") }
      securitySettings
        .tabItem { Label("settings.security", systemImage: "lock.shield") }
      advancedSettings
        .tabItem { Label("settings.advanced", systemImage: "slider.horizontal.3") }
    }
    .padding()
    .confirmationDialog(
      "source.revoke.confirmation.title",
      isPresented: Binding(
        get: { pendingRevocationSourceID != nil },
        set: { if !$0 { pendingRevocationSourceID = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("source.revoke.confirmation.action", role: .destructive) {
        if let sourceID = pendingRevocationSourceID {
          model.revokeSource(sourceID)
        }
        pendingRevocationSourceID = nil
      }
      Button("action.cancel", role: .cancel) {
        pendingRevocationSourceID = nil
      }
    } message: {
      Text("source.revoke.confirmation.message")
    }
    .confirmationDialog(
      "settings.audit.clear-confirmation.title",
      isPresented: $isAuditClearConfirmationPresented,
      titleVisibility: .visible
    ) {
      Button("settings.audit.clear", role: .destructive) {
        model.clearActionAudit()
      }
      Button("action.cancel", role: .cancel) {}
    } message: {
      Text("settings.audit.clear-confirmation.message")
    }
    .sheet(isPresented: toolImportIsPresented) {
      if let preview = model.toolImportPreview {
        ToolDefinitionImportPreviewView(
          preview: preview,
          cancelAction: model.cancelToolImport,
          importAction: model.confirmToolImport
        )
      }
    }
    .alert("runtime.error.title", isPresented: runtimeErrorIsPresented) {
      Button("action.ok") { model.dismissRuntimeError() }
    } message: {
      if let error = model.runtimeError { Text(error.message) }
    }
  }

  private var generalSettings: some View {
    Form {
      Section("settings.scanning.section") {
        Toggle(
          "settings.scan-on-launch",
          isOn: Binding(
            get: { model.scanOnLaunch },
            set: { model.setScanOnLaunch($0) }
          )
        )
      }

      Section("settings.menu-bar.section") {
        Toggle("settings.menu-bar.enabled", isOn: $isMenuBarEnabled)
        Text("settings.menu-bar.description")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("settings.age.section") {
        LabeledContent("settings.old-after") {
          TextField("settings.days", value: oldModelThresholdBinding, format: .number)
            .frame(width: 64)
            .multilineTextAlignment(.trailing)
          Text("settings.days")
          Stepper("settings.old-after", value: oldModelThresholdBinding, in: 1...3_650)
            .labelsHidden()
            .accessibilityLabel(Text("settings.old-after"))
        }

        HStack {
          Text("settings.age.presets")
          Spacer()
          ForEach([30, 90, 180], id: \.self) { days in
            Button("\(days)") {
              model.setOldModelThresholdDays(days)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(days) \(String(localized: "settings.days"))")
          }
        }
      }
    }
  }

  private var sourceSettings: some View {
    Form {
      Section("settings.sources.section") {
        ForEach(model.sources) { source in
          Toggle(
            source.displayName,
            isOn: Binding(
              get: { source.isEnabled },
              set: { model.setSourceEnabled(source.id, enabled: $0) }
            )
          )
        }
        Button("source.add-folder.action") {
          model.addManualFolder()
        }
      }

      Section("settings.volumes.section") {
        ForEach(model.mountedVolumes) { volume in
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
              Text(volume.name)
              Text(volume.rootURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
              HStack(spacing: 5) {
                Text(volume.fileSystem)
                Text("·")
                Text(volume.isReadOnly ? "volume.read-only" : "volume.read-write")
                if let available = volume.availableByteCount,
                  let total = volume.totalByteCount
                {
                  Text("·")
                  Text("\(wholeByteCount(available)) / \(wholeByteCount(total))")
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            Spacer()
            Button("volume.add.action") {
              model.addManualFolder(startingAt: volume.rootURL)
            }
          }
        }
        Button("volume.refresh.action", systemImage: "arrow.clockwise") {
          model.refreshMountedVolumes()
        }
      }
    }
  }

  private var integrationSettings: some View {
    Form {
      Section("settings.runtimes.section") {
        LabeledContent("Ollama") {
          Text("settings.runtime.local-api")
            .foregroundStyle(.secondary)
        }

        ForEach(model.toolDefinitions, id: \.id) { (definition: ToolDefinition) in
          VStack(alignment: .leading, spacing: 8) {
            Toggle(
              definition.displayName,
              isOn: Binding(
                get: { definition.isEnabled },
                set: { model.setToolEnabled(definition.id, enabled: $0) }
              )
            )
            Text(definition.executableURL.path)
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)

            HStack {
              Text(
                model.isToolApproved(definition)
                  ? String(localized: "tool.approved") : String(localized: "tool.not-approved")
              )
              .font(.caption)
              .foregroundStyle(
                model.isToolApproved(definition) ? Color.secondary : Color.orange
              )
              Spacer()
              Button("tool.choose.action") {
                if let runtimeID = definition.runtimeAdapterID {
                  model.chooseRuntimeExecutable(runtimeID)
                }
              }
              .disabled(definition.runtimeAdapterID == nil)
              Button("tool.validate.action") {
                model.validateTool(definition.id)
              }
              Button("inventory.reveal.action", systemImage: "folder") {
                model.revealTool(definition.id)
              }
              .labelStyle(.iconOnly)
              Button("tool.export.action") {
                model.exportToolDefinition(definition.id)
              }
              Button("tool.reset.action") {
                if let runtimeID = definition.runtimeAdapterID {
                  model.resetRuntimeTool(runtimeID)
                }
              }
              .disabled(definition.runtimeAdapterID == nil)
            }

            if let validation = definition.lastValidation {
              HStack(spacing: 6) {
                Text(validation.signingStatus.rawValue.capitalized)
                if let identifier = validation.signingIdentifier {
                  Text("·")
                  Text(identifier)
                }
                if let version = validation.version {
                  Text("·")
                  Text(version)
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            LabeledContent("tool.origin", value: definition.origin.displayName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        ForEach(model.missingRuntimeToolTemplates) { template in
          Button {
            model.chooseRuntimeExecutable(template.runtimeAdapterID)
          } label: {
            Label(
              "\(String(localized: "tool.choose.action")) \(template.displayName)…",
              systemImage: "plus"
            )
          }
        }
        Button("tool.import.action", systemImage: "square.and.arrow.down") {
          model.importToolDefinition()
        }
        Text("tool.export.privacy")
          .font(.caption)
          .foregroundStyle(.secondary)
        adapterGuideLink
      }

      Section("settings.storage-providers.section") {
        ForEach(model.availableStorageProviderIDs, id: \.self) { providerID in
          LabeledContent(providerID.localizedName) {
            Text("settings.integration.built-in")
              .foregroundStyle(.secondary)
          }
        }
        adapterGuideLink
      }
    }
  }

  private var securitySettings: some View {
    Form {
      Section("settings.security.section") {
        Text("settings.security.description")
        ForEach(model.sources) { source in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                Text(source.rootURL.path)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(source.accessState.localizedName)
                .foregroundStyle(
                  source.accessState == .allowed ? Color.secondary : Color.orange
                )
            }
            HStack {
              Button("source.grant-again.action") {
                model.grantAccessAgain(to: source.id)
              }
              Spacer()
              Button("source.revoke.action", role: .destructive) {
                pendingRevocationSourceID = source.id
              }
            }
          }
        }
      }

      Section("settings.audit.section") {
        if model.actionAuditEntries.isEmpty {
          Text("settings.audit.empty")
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.actionAuditEntries) { entry in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(entry.occurredAt, format: .dateTime.year().month().day().hour().minute())
                Text(entry.providerIDs.map(\.localizedName).joined(separator: ", "))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(deletionResultKey(entry.status))
                .foregroundStyle(.secondary)
              Text("\(entry.succeededCount)/\(entry.operationCount)")
                .monospacedDigit()
            }
          }
          Button("settings.audit.clear", role: .destructive) {
            isAuditClearConfirmationPresented = true
          }
        }
        Text("settings.audit.privacy")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var advancedSettings: some View {
    Form {
      Section("settings.inventory.section") {
        Text("settings.inventory.ephemeral")
          .foregroundStyle(.secondary)
      }
      Section("settings.extension.section") {
        Text("settings.extension.description")
          .foregroundStyle(.secondary)
        adapterGuideLink
      }
    }
  }

  private var adapterGuideLink: some View {
    Group {
      if let adapterGuideURL = URL(
        string: "https://github.com/powtac/wtm/blob/main/docs/adapters.md"
      ) {
        Link("settings.extend.action", destination: adapterGuideURL)
      }
    }
  }

  private var oldModelThresholdBinding: Binding<Int> {
    Binding(
      get: { model.oldModelThresholdDays },
      set: { model.setOldModelThresholdDays($0) }
    )
  }

  private var toolImportIsPresented: Binding<Bool> {
    Binding(
      get: { model.toolImportPreview != nil },
      set: { if !$0 { model.cancelToolImport() } }
    )
  }

  private var runtimeErrorIsPresented: Binding<Bool> {
    Binding(
      get: { model.runtimeError != nil },
      set: { if !$0 { model.dismissRuntimeError() } }
    )
  }
}
