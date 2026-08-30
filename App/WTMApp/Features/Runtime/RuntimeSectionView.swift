import SwiftUI
import WTMDomain
import WTMRuntime

struct RuntimeSectionView: View {
  @Bindable var model: InventoryViewModel
  let installation: ModelInstallation

  var body: some View {
    let runtimeIDs = model.runtimeOptions(for: installation)
    Section("runtime.section") {
      if runtimeIDs.isEmpty {
        Text(
          installation.variant.format == .mlx
            ? "runtime.mlx.unavailable"
            : "runtime.unsupported"
        )
        .foregroundStyle(.secondary)
      } else {
        ForEach(runtimeIDs, id: \.self) { runtimeID in
          runtimeRow(runtimeID)
        }
      }
    }
  }

  @ViewBuilder
  private func runtimeRow(_ runtimeID: RuntimeAdapterID) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(runtimeID.localizedName)
          .font(.headline)
        Spacer()
        if model.isCheckingRuntime || model.isPreparingRuntime || model.isRunningRuntimeAction {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(Text("accessibility.runtime.checking"))
        }
      }

      if let readiness = model.readiness(for: installation, runtimeID: runtimeID) {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
          statusRow("runtime.integrity", value: readiness.integrity.value.displayName)
          statusRow("runtime.compatibility", value: readiness.compatibility.value.displayName)
          statusRow("runtime.validation", value: readiness.validation.value.displayName)
          statusRow("runtime.state", value: readiness.runtime.value.displayName)
          if let estimate = readiness.estimatedMemory {
            statusRow("runtime.memory-estimate", value: wholeByteCount(estimate.byteCount))
          }
        }
        .font(.callout)

        ForEach(readiness.blockers, id: \.self) { blocker in
          Label(blocker, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        HStack(spacing: 4) {
          Text(readiness.validation.checkedAt, format: .dateTime.hour().minute().second())
          Text("·")
          Text("\(runtimeID.localizedName) v\(readiness.validation.adapterVersion)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Text("runtime.not-checked")
          .font(.callout)
          .foregroundStyle(.secondary)
      }

      HStack {
        Button("runtime.check.action") {
          model.checkRuntimeReadiness(runtimeID, for: installation)
        }
        .accessibilityIdentifier("runtime-check-\(runtimeID.rawValue)")
        .accessibilityLabel(Text("Check \(runtimeID.localizedName) readiness"))
        if let readiness = model.readiness(for: installation, runtimeID: runtimeID) {
          if readiness.compatibility.value == .compatible {
            Button("runtime.test.action") {
              model.prepareRuntimeTest(runtimeID, for: installation)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPreparingRuntime || model.isRunningRuntimeAction)
            .accessibilityIdentifier("runtime-test-\(runtimeID.rawValue)")
            .accessibilityLabel(Text("Test \(runtimeID.localizedName) with this model"))
          } else {
            Button("runtime.try-anyway.action") {
              model.prepareRuntimeTest(runtimeID, for: installation)
            }
            .disabled(model.isPreparingRuntime || model.isRunningRuntimeAction)
            .accessibilityIdentifier("runtime-test-\(runtimeID.rawValue)")
            .accessibilityLabel(Text("Try \(runtimeID.localizedName) with this model anyway"))
          }
        }
      }

      if let session = model.latestRuntimeSession(for: installation, runtimeID: runtimeID) {
        Divider()
        runtimeSession(session)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func runtimeSession(_ session: RuntimeSessionSnapshot) -> some View {
    LabeledContent("runtime.state", value: session.instance.state.displayName)
    LabeledContent("runtime.endpoint", value: session.instance.endpoint.absoluteString)
    LabeledContent("runtime.ownership", value: session.instance.ownership.displayName)
    if let health = session.health {
      LabeledContent("runtime.health", value: health.summary)
    }
    if let inference = session.inference {
      LabeledContent("runtime.inference", value: inference.summary)
    }

    if !session.logs.isEmpty {
      DisclosureGroup("runtime.logs") {
        ForEach(session.logs) { entry in
          Text("[\(entry.stream.shortName)] \(entry.message)")
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }

    HStack {
      Button("runtime.refresh.action", systemImage: "arrow.clockwise") {
        model.refreshRuntimeSession(session.instance.id)
      }
      if session.instance.ownership == .startedByWTM,
        session.instance.state == .running || session.instance.state == .starting
      {
        Button("runtime.stop.action", systemImage: "stop.circle", role: .destructive) {
          model.stopRuntimeSession(session.instance.id)
        }
      }
    }
  }

  @ViewBuilder
  private func statusRow(_ key: LocalizedStringKey, value: String) -> some View {
    GridRow {
      Text(key)
        .foregroundStyle(.secondary)
      Text(value)
        .gridColumnAlignment(.leading)
    }
  }
}

extension ModelIntegrity {
  fileprivate var displayName: String { rawValue.displayName }
}

extension RuntimeCompatibility {
  fileprivate var displayName: String { rawValue.displayName }
}

extension ModelValidation {
  fileprivate var displayName: String { rawValue.displayName }
}

extension RuntimeState {
  fileprivate var displayName: String { rawValue.displayName }
}

extension RuntimeOwnership {
  fileprivate var displayName: String { rawValue.displayName }
}

extension RuntimeLogStream {
  fileprivate var shortName: String {
    switch self {
    case .standardOutput: "out"
    case .standardError: "err"
    case .system: "system"
    }
  }
}

extension String {
  fileprivate var displayName: String {
    unicodeScalars.reduce(into: "") { result, scalar in
      if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
        result.append(" ")
      }
      result.append(Character(String(scalar).lowercased()))
    }
    .capitalized
  }
}
