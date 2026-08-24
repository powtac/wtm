import SwiftUI
import WTMDomain

struct DeletionPreviewView: View {
  let plan: DeletionPlan
  let isExecuting: Bool
  let cancelAction: () -> Void
  let executeAction: (Bool) -> Void

  @State private var confirmedIrreversible = false

  var body: some View {
    Form {
      Section("deletion.preview.models") {
        ForEach(plan.models) { model in
          LabeledContent(model.displayName) {
            Text(model.providerID.localizedName)
          }
        }
      }

      Section("deletion.preview.operations") {
        ForEach(plan.operations) { operation in
          HStack(alignment: .firstTextBaseline) {
            Image(
              systemName: operation.reversibility == .trash
                ? "trash"
                : "exclamationmark.triangle"
            )
            .foregroundStyle(
              operation.reversibility == .trash ? Color.secondary : Color.red
            )
            VStack(alignment: .leading, spacing: 2) {
              Text(operationDisplayName(operation))
              Text(reversibilityKey(operation.reversibility))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(wholeByteCount(operation.expectedReclaimableByteCount))
              .monospacedDigit()
          }
          .accessibilityElement(children: .combine)
        }
      }

      if !plan.retainedDependencies.isEmpty {
        Section("deletion.preview.retained") {
          ForEach(plan.retainedDependencies) { dependency in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(dependency.displayName)
                Text(retainedReasonKey(dependency.reason))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(wholeByteCount(dependency.allocatedByteCount))
                .monospacedDigit()
            }
          }
        }
      }

      if !plan.conflicts.isEmpty {
        Section("deletion.preview.conflicts") {
          ForEach(plan.conflicts) { conflict in
            Label(conflictReasonKey(conflict.reason), systemImage: "exclamationmark.octagon")
              .foregroundStyle(.red)
          }
        }
      }

      Section("deletion.preview.estimate") {
        LabeledContent(
          "deletion.preview.expected-reclaim",
          value: wholeByteCount(plan.expectedReclaimableByteCount)
        )
        Text("deletion.preview.estimate-help")
          .font(.caption)
          .foregroundStyle(.secondary)
        LabeledContent(
          "deletion.preview.expires",
          value: plan.expiresAt.formatted(date: .omitted, time: .shortened)
        )
      }

      if plan.providerPlans.flatMap({ $0.warnings }).contains(.externalUsageNotVerified) {
        Section {
          Label("deletion.warning.external-usage", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
      }

      if plan.requiresIrreversibleConfirmation {
        Section("deletion.irreversible.title") {
          Text("deletion.irreversible.message")
            .foregroundStyle(.red)
          Toggle("deletion.irreversible.confirmation", isOn: $confirmedIrreversible)
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle(Text("deletion.preview.title"))
    .frame(minWidth: 620, minHeight: 560)
    .safeAreaInset(edge: .bottom) {
      HStack {
        Button("action.cancel", role: .cancel) { cancelAction() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        if isExecuting {
          ProgressView()
            .controlSize(.small)
          Text("deletion.executing")
            .foregroundStyle(.secondary)
        }
        Button(executeButtonKey, role: .destructive) {
          executeAction(confirmedIrreversible)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          isExecuting || !plan.conflicts.isEmpty
            || (plan.requiresIrreversibleConfirmation && !confirmedIrreversible)
        )
      }
      .padding()
      .background(.bar)
    }
  }

  private var executeButtonKey: LocalizedStringKey {
    plan.requiresIrreversibleConfirmation
      ? "deletion.execute.irreversible"
      : "deletion.execute.trash"
  }
}

func operationDisplayName(_ operation: DeletionOperation) -> String {
  switch operation.payload {
  case .trash(let target): target.displayName
  case .provider(let request): request.identifier
  }
}

func reversibilityKey(_ reversibility: DeletionReversibility) -> LocalizedStringResource {
  switch reversibility {
  case .trash: "deletion.reversible.trash"
  case .irreversible: "deletion.reversible.irreversible"
  }
}

func retainedReasonKey(_ reason: RetainedDependencyReason) -> LocalizedStringResource {
  switch reason {
  case .remainingReference: "deletion.retained.remaining-reference"
  case .protectedIdentityOrSecret: "deletion.retained.protected"
  case .unknownOwnership: "deletion.retained.unknown"
  }
}

func conflictReasonKey(_ reason: DeletionConflictReason) -> LocalizedStringResource {
  switch reason {
  case .overlappingTargets: "deletion.conflict.overlap"
  case .providerMismatch: "deletion.conflict.provider"
  case .modelInUse: "deletion.conflict.in-use"
  }
}

func deletionResultKey(_ status: DeletionExecutionStatus) -> LocalizedStringResource {
  switch status {
  case .succeeded: "deletion.result.succeeded"
  case .partial: "deletion.result.partial"
  case .blocked: "deletion.result.blocked"
  case .failed: "deletion.result.failed"
  }
}
