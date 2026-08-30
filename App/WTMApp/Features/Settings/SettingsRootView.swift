import SwiftUI
import WTMDomain

struct SettingsRootView: View {
  @Bindable var model: InventoryViewModel
  let updateChecker: UpdateChecker
  @AppStorage("menu-bar.enabled") private var isMenuBarEnabled = true
  @State private var confirmation: SettingsConfirmation?

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
    }
    .scenePadding()
    .confirmationDialog(
      confirmationTitle,
      isPresented: confirmationIsPresented,
      titleVisibility: .visible
    ) {
      confirmationActions
    } message: {
      Text(confirmationMessage)
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
    .alert("settings.login-item.error-title", isPresented: launchAtLoginErrorIsPresented) {
      Button("action.ok") { model.dismissLaunchAtLoginError() }
    } message: {
      if let error = model.launchAtLoginError { Text(error) }
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

      Section("settings.age.section") {
        LabeledContent("settings.old-after") {
          HStack(spacing: 8) {
            TextField("settings.days", value: oldModelThresholdBinding, format: .number)
              .frame(width: 64)
              .multilineTextAlignment(.trailing)
            Text("settings.days")
              .fixedSize()
            Stepper("settings.old-after", value: oldModelThresholdBinding, in: 1...3_650)
              .labelsHidden()
              .accessibilityLabel(Text("settings.old-after"))
          }
        }

        LabeledContent("settings.age.presets") {
          HStack(spacing: 6) {
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

      Section("settings.updates.section") {
        UpdateStatusView(checker: updateChecker)
      }

      Section {
        Toggle("settings.menu-bar.enabled", isOn: $isMenuBarEnabled)
        Toggle(
          "settings.login-item.enabled",
          isOn: Binding(
            get: { model.isLaunchAtLoginEnabled },
            set: { model.setLaunchAtLogin($0) }
          )
        )
      } header: {
        Text("settings.menu-bar.section")
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          Text("settings.menu-bar.description")
          Text("settings.login-item.description")
        }
      }

      Section("settings.inventory.section") {
        Text("settings.inventory.ephemeral")
          .foregroundStyle(.secondary)
      }

      Section("settings.defaults.section") {
        Text("settings.defaults.description")
          .foregroundStyle(.secondary)
        Button("settings.reset.action", role: .destructive) {
          confirmation = .resetDefaults
        }
        .disabled(model.isPreparingDeletion || model.isDeleting)
      }
    }
    .formStyle(.grouped)
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

        HStack {
          Button("source.add-folder.action", systemImage: "folder.badge.plus") {
            model.addManualFolder()
          }
          Button("source.add-mlx-folder.action", systemImage: "folder.badge.plus") {
            model.addMLXFolder()
          }
        }
      }

      Section("settings.volumes.section") {
        ForEach(model.mountedVolumes) { volume in
          LabeledContent {
            Button("volume.add.action") {
              model.addManualFolder(startingAt: volume.rootURL)
            }
            .accessibilityLabel(Text("Add \(volume.name) as a model source"))
          } label: {
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
          }
        }

        Button("volume.refresh.action", systemImage: "arrow.clockwise") {
          model.refreshMountedVolumes()
        }
      }
    }
    .formStyle(.grouped)
  }

  private var integrationSettings: some View {
    Form {
      Section("settings.runtimes.section") {
        LabeledContent("settings.runtime.ollama") {
          Text("settings.runtime.local-api")
            .foregroundStyle(.secondary)
        }

        ForEach(model.toolDefinitions, id: \.id) { (definition: ToolDefinition) in
          runtimeToolRow(definition)
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
        adapterGuideLink(anchor: "runtime-adapter")
      }

      Section("settings.storage-providers.section") {
        ForEach(model.availableStorageProviderIDs, id: \.self) { providerID in
          LabeledContent(providerID.localizedName) {
            Text("settings.integration.built-in")
              .foregroundStyle(.secondary)
          }
        }
        adapterGuideLink(anchor: "storage-provider-adapter")
      }

      Section("settings.clients.section") {
        ForEach(model.availableClientIDs, id: \.self) { clientID in
          LabeledContent(clientID.displayName) {
            Text("settings.client.reviewed")
              .foregroundStyle(.secondary)
          }
        }
        Text("settings.clients.description")
          .font(.caption)
          .foregroundStyle(.secondary)
        adapterGuideLink(anchor: "client-adapter")
      }

      Section("settings.extension.section") {
        Text("settings.extension.description")
          .foregroundStyle(.secondary)
        adapterGuideLink(anchor: "choose")
      }
    }
    .formStyle(.grouped)
  }

  private func runtimeToolRow(_ definition: ToolDefinition) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Toggle(
          definition.displayName,
          isOn: Binding(
            get: { definition.isEnabled },
            set: { model.setToolEnabled(definition.id, enabled: $0) }
          )
        )
        Spacer(minLength: 8)
        Menu {
          Button("tool.choose.action", systemImage: "folder") {
            if let runtimeID = definition.runtimeAdapterID {
              model.chooseRuntimeExecutable(runtimeID)
            }
          }
          .disabled(definition.runtimeAdapterID == nil)
          Button("tool.validate.action", systemImage: "checkmark.shield") {
            model.validateTool(definition.id)
          }
          Button("inventory.reveal.action", systemImage: "arrow.turn.down.right") {
            model.revealTool(definition.id)
          }
          Button("tool.export.action", systemImage: "square.and.arrow.up") {
            model.exportToolDefinition(definition.id)
          }
          Button("tool.reset.action", systemImage: "arrow.counterclockwise") {
            if let runtimeID = definition.runtimeAdapterID {
              model.resetRuntimeTool(runtimeID)
            }
          }
          .disabled(definition.runtimeAdapterID == nil)
        } label: {
          Image(systemName: "ellipsis.circle")
            .accessibilityLabel(Text("Actions"))
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("Actions for \(definition.displayName)"))
      }

      Text(definition.executableURL.path)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      HStack(spacing: 6) {
        Text(
          model.isToolApproved(definition)
            ? String(localized: "tool.approved") : String(localized: "tool.not-approved")
        )
        .font(.caption)
        .foregroundStyle(model.isToolApproved(definition) ? Color.secondary : Color.orange)

        if let validation = definition.lastValidation {
          Text("·")
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
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      LabeledContent("tool.origin", value: definition.origin.displayName)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var securitySettings: some View {
    Form {
      Section("settings.security.section") {
        Text("settings.security.description")
          .foregroundStyle(.secondary)
        ForEach(model.sources) { source in
          VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
              Text(source.accessState.localizedName)
                .foregroundStyle(
                  source.accessState == .allowed ? Color.secondary : Color.orange
                )
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                Text(source.rootURL.path)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            HStack {
              Button("source.grant-again.action") {
                model.grantAccessAgain(to: source.id)
              }
              Spacer()
              Button("source.revoke.action", role: .destructive) {
                confirmation = .revokeSource(source.id)
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
            confirmation = .clearAudit
          }
        }
        Text("settings.audit.privacy")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  private func resetToDefaults() {
    isMenuBarEnabled = true
    UserDefaults.standard.removeObject(forKey: "inventory.storage-display-mode")
    UserDefaults.standard.removeObject(forKey: "inventory.table-columns")
    model.setLaunchAtLogin(false)
    model.resetToDefaults()
  }

  private func adapterGuideLink(anchor: String) -> some View {
    Group {
      if let adapterGuideURL = URL(
        string: "https://powtac.github.io/wtm/extend.html#\(anchor)"
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

  private var confirmationIsPresented: Binding<Bool> {
    Binding(
      get: { confirmation != nil },
      set: { if !$0 { confirmation = nil } }
    )
  }

  private var confirmationTitle: LocalizedStringKey {
    switch confirmation {
    case .revokeSource: return "source.revoke.confirmation.title"
    case .clearAudit: return "settings.audit.clear-confirmation.title"
    case .resetDefaults: return "settings.reset.confirmation.title"
    case nil: return "action.cancel"
    }
  }

  private var confirmationMessage: LocalizedStringKey {
    switch confirmation {
    case .revokeSource: return "source.revoke.confirmation.message"
    case .clearAudit: return "settings.audit.clear-confirmation.message"
    case .resetDefaults: return "settings.reset.confirmation.message"
    case nil: return "action.cancel"
    }
  }

  @ViewBuilder
  private var confirmationActions: some View {
    switch confirmation {
    case .revokeSource(let sourceID):
      Button("source.revoke.confirmation.action", role: .destructive) {
        model.revokeSource(sourceID)
        confirmation = nil
      }
      Button("action.cancel", role: .cancel) {
        confirmation = nil
      }
    case .clearAudit:
      Button("settings.audit.clear", role: .destructive) {
        model.clearActionAudit()
        confirmation = nil
      }
      Button("action.cancel", role: .cancel) {
        confirmation = nil
      }
    case .resetDefaults:
      Button("settings.reset.action", role: .destructive) {
        resetToDefaults()
        confirmation = nil
      }
      Button("action.cancel", role: .cancel) {
        confirmation = nil
      }
    case nil:
      Button("action.cancel", role: .cancel) {
        confirmation = nil
      }
    }
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

  private var launchAtLoginErrorIsPresented: Binding<Bool> {
    Binding(
      get: { model.launchAtLoginError != nil },
      set: { if !$0 { model.dismissLaunchAtLoginError() } }
    )
  }
}

private enum SettingsConfirmation: Equatable {
  case revokeSource(ScanSource.ID)
  case clearAudit
  case resetDefaults
}
