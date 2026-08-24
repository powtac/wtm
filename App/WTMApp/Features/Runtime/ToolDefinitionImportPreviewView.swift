import SwiftUI
import WTMDomain

struct ToolDefinitionImportPreviewView: View {
  let preview: ToolDefinitionImportPreview
  let cancelAction: () -> Void
  let importAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("tool.import.preview.title", systemImage: "doc.badge.plus")
        .font(.headline)
      Text("tool.import.preview.message")
        .foregroundStyle(.secondary)

      Form {
        LabeledContent("tool.import.name", value: preview.definition.displayName)
        LabeledContent(
          "tool.import.runtime",
          value: preview.definition.runtimeAdapterID?.localizedName
            ?? String(localized: "value.unknown")
        )
        LabeledContent("runtime.plan.path", value: preview.definition.executableURL.path)
        LabeledContent("tool.origin", value: preview.definition.origin.displayName)
        LabeledContent("tool.import.state", value: String(localized: "tool.import.disabled"))
        LabeledContent("tool.import.formats") {
          Text(
            preview.definition.supportedFormats
              .map(\.localizedName)
              .sorted()
              .joined(separator: ", ")
          )
        }
        LabeledContent("runtime.plan.arguments") {
          VStack(alignment: .trailing, spacing: 2) {
            ForEach(Array(preview.definition.arguments.enumerated()), id: \.offset) { item in
              Text(argumentText(item.element))
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
          }
        }
        if let endpoint = preview.definition.localAPIBaseURL {
          LabeledContent("runtime.endpoint", value: endpoint.absoluteString)
        }
        if let directory = preview.definition.currentDirectoryURL {
          LabeledContent("tool.import.working-directory", value: directory.path)
        }
        if !preview.definition.environment.isEmpty {
          LabeledContent("tool.import.environment") {
            VStack(alignment: .trailing, spacing: 2) {
              ForEach(preview.definition.environment.keys.sorted(), id: \.self) { key in
                Text("\(key)=\(preview.definition.environment[key] ?? "")")
                  .font(.caption.monospaced())
                  .textSelection(.enabled)
              }
            }
          }
        }
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button("action.cancel", action: cancelAction)
          .keyboardShortcut(.cancelAction)
        Button("tool.import.confirm", action: importAction)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(minWidth: 620, idealWidth: 680, minHeight: 500)
  }

  private func argumentText(_ argument: ToolArgument) -> String {
    switch argument {
    case .literal(let value): value
    case .placeholder(let placeholder): "{\(placeholder.rawValue)}"
    }
  }
}
