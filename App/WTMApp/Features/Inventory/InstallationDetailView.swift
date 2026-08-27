import SwiftUI
import WTMDomain

struct InstallationDetailView: View {
  @Bindable var model: InventoryViewModel
  let installation: ModelInstallation?
  let sourceName: String?
  let revealAction: (URL) -> Void
  let deleteAction: () -> Void
  let canDelete: Bool

  var body: some View {
    if let installation {
      Form {
        LabeledContent("detail.source-type", value: installation.inventorySourceTypeName)
        if let sourceName {
          LabeledContent("detail.source", value: sourceName)
        }
        LabeledContent("detail.format", value: installation.variant.format.localizedName)
        LabeledContent(
          "detail.size",
          value: wholeByteCount(installation.allocatedByteCount)
        )
        LabeledContent(
          "detail.exact-size",
          value: installation.allocatedByteCount.formatted()
        )
        LabeledContent("detail.path", value: installation.rootURL.path)
        LabeledContent("detail.age", value: installationAgeText(installation))
        if let timestamp = installation.earliestChangeTimestamp {
          LabeledContent(
            "detail.first-change",
            value: timestamp.value.formatted(date: .abbreviated, time: .shortened)
          )
          LabeledContent("detail.age-basis", value: timestamp.kind.localizedName)
        }

        Section {
          ForEach(artifactsSortedByName(installation.artifacts)) { artifact in
            HStack {
              Text(artifact.url.lastPathComponent)
              Spacer()
              Text(
                wholeByteCount(artifact.allocatedByteCount)
              )
              .foregroundStyle(.secondary)
              if artifact.isShared {
                Text("artifact.shared")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else if artifact.physicalIdentifier == nil {
                Text("artifact.unknown")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }
            }
          }
        } header: {
          Text(artifactSectionTitle(count: installation.artifacts.count))
        }

        if !installation.configurationURLs.isEmpty {
          Section("detail.configurations") {
            ForEach(installation.configurationURLs.sorted(by: { $0.path < $1.path }), id: \.self) {
              url in
              HStack {
                Text(url.lastPathComponent)
                Spacer()
                Button("inventory.reveal.action", systemImage: "folder") {
                  revealAction(url)
                }
                .labelStyle(.iconOnly)
              }
            }
          }
        }

        Button("inventory.reveal.action", systemImage: "folder") {
          revealAction(installation.rootURL)
        }

        if let modelCardURL = validatedModelCardURL(installation.modelCard) {
          Link("detail.model-card.action", destination: modelCardURL)
        }

        RuntimeSectionView(model: model, installation: installation)
        ClientSectionView(model: model, installation: installation)

        Section {
          Button("deletion.review.action", systemImage: "trash", role: .destructive) {
            deleteAction()
          }
          .keyboardShortcut(.delete, modifiers: [.command])
          .disabled(!canDelete)
        }
      }
      .formStyle(.grouped)
      .navigationTitle(installation.identity.displayName)
    } else {
      ContentUnavailableView(
        "detail.empty.title",
        systemImage: "sidebar.right",
        description: Text("detail.empty.description")
      )
    }
  }
}
