import SwiftUI
import WTMDomain

struct InstallationDetailView: View {
  let installation: ModelInstallation?

  var body: some View {
    if let installation {
      Form {
        LabeledContent("detail.provider", value: installation.providerID.localizedName)
        LabeledContent("detail.format", value: installation.variant.format.localizedName)
        LabeledContent(
          "detail.size",
          value: ByteCountFormatter.string(
            fromByteCount: installation.allocatedByteCount,
            countStyle: .decimal
          )
        )
        LabeledContent("detail.path", value: installation.rootURL.path)

        Section("detail.artifacts") {
          ForEach(installation.artifacts) { artifact in
            HStack {
              Text(artifact.url.lastPathComponent)
              Spacer()
              Text(
                ByteCountFormatter.string(
                  fromByteCount: artifact.allocatedByteCount,
                  countStyle: .decimal
                )
              )
              .foregroundStyle(.secondary)
            }
          }
        }

        if let modelCard = installation.modelCard {
          Link("detail.model-card.action", destination: modelCard.url)
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
