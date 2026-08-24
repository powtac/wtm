import SwiftUI
import WTMDomain

struct RuntimePlanPreviewView: View {
  let preview: RuntimePlanPreview
  let cancelAction: () -> Void
  let executeAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("runtime.plan.warning", systemImage: "memorychip")
        .font(.headline)
        .accessibilityIdentifier("runtime-plan-title")
      Text("runtime.plan.warning-detail")
        .foregroundStyle(.secondary)

      Form {
        LabeledContent("runtime.plan.runtime", value: preview.runtimeName)
        LabeledContent("runtime.plan.model", value: preview.installation.identity.displayName)
        LabeledContent("runtime.endpoint", value: preview.plan.endpoint.absoluteString)
        if let estimate = preview.plan.estimatedMemory {
          LabeledContent("runtime.memory-estimate", value: wholeByteCount(estimate.byteCount))
          Text(estimate.basis)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        LabeledContent("runtime.plan.stop-behavior", value: stopBehaviorText)

        switch preview.plan.strategy {
        case .providerManaged:
          Text("runtime.plan.provider-managed")
            .foregroundStyle(.secondary)
        case .executable(let invocation):
          Section("runtime.plan.executable") {
            LabeledContent("runtime.plan.path", value: invocation.executableURL.path)
            if let validation = preview.validation {
              LabeledContent("runtime.plan.signature", value: validation.signingStatus.rawValue)
              if let version = validation.version {
                LabeledContent("runtime.plan.version", value: version)
              }
            }
            LabeledContent("runtime.plan.arguments") {
              VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(invocation.arguments.enumerated()), id: \.offset) { item in
                  Text(item.element)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("runtime-argument-\(item.offset)")
                    .accessibilityLabel(item.element)
                }
              }
            }
          }
        }

        if preview.requiresApproval {
          Label("runtime.plan.approval-required", systemImage: "checkmark.shield")
            .foregroundStyle(.orange)
        }
        Label("runtime.plan.inference", systemImage: "checkmark.bubble")
          .foregroundStyle(.secondary)
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button("action.cancel", action: cancelAction)
          .keyboardShortcut(.cancelAction)
        Button("runtime.plan.execute", action: executeAction)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(minWidth: 620, idealWidth: 680, minHeight: 520)
  }

  private var stopBehaviorText: String {
    switch preview.plan.stopBehavior {
    case .stopOwnedProcess: String(localized: "runtime.stop.owned")
    case .providerStopUnavailable: String(localized: "runtime.stop.unavailable")
    case .stopProviderInstance: String(localized: "runtime.stop.provider")
    }
  }
}
