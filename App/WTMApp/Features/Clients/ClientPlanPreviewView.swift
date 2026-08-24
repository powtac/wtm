import SwiftUI
import WTMDomain

struct ClientPlanPreviewView: View {
  let preview: ClientPlanPreview
  let cancelAction: () -> Void
  let executeAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("client.preview.warning", systemImage: "arrow.up.forward.app")
        .font(.title2.bold())
      Text("client.preview.detail")
        .foregroundStyle(.secondary)

      Form {
        LabeledContent("client.preview.client", value: preview.clientName)
        LabeledContent("client.preview.model", value: preview.plan.modelReference)
        LabeledContent("runtime.endpoint", value: preview.plan.endpoint.absoluteString)
        if case .executable(let handoff) = preview.plan.strategy {
          LabeledContent("runtime.plan.path", value: handoff.invocation.executableURL.path)
          LabeledContent("runtime.plan.arguments") {
            VStack(alignment: .trailing, spacing: 3) {
              ForEach(Array(handoff.invocation.arguments.enumerated()), id: \.offset) { item in
                Text(item.element)
                  .font(.caption.monospaced())
                  .textSelection(.enabled)
              }
            }
          }
        }
      }

      HStack {
        Spacer()
        Button("action.cancel", action: cancelAction)
        Button("client.execute.action", action: executeAction)
          .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 620)
  }
}
