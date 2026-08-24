import Foundation
import OSLog
import Observation
import WTMDomain
import WTMInventory

@MainActor
@Observable
final class InventoryViewModel {
  private(set) var sources: [ScanSource]
  private(set) var installations: [ModelInstallation] = []
  private(set) var issues: [InventoryIssue] = []
  private(set) var lastScanDate: Date?
  private(set) var isScanning = false
  var selectedSection = InventorySection.all
  var selectedInstallationID: ModelInstallation.ID?
  var searchText = ""

  private let coordinator: InventoryCoordinator?
  private let folderSelector: any FolderSelecting
  private let fileRevealer: any FileRevealing
  private var scanTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "de.powtac.whatthemodel", category: "inventory")

  init(
    coordinator: InventoryCoordinator?,
    initialSources: [ScanSource],
    folderSelector: any FolderSelecting,
    fileRevealer: any FileRevealing
  ) {
    self.coordinator = coordinator
    sources = initialSources
    self.folderSelector = folderSelector
    self.fileRevealer = fileRevealer
  }

  isolated deinit {
    scanTask?.cancel()
  }

  var visibleInstallations: [ModelInstallation] {
    installations.filter { installation in
      let matchesSection: Bool
      switch selectedSection {
      case .all, .providers:
        matchesSection = true
      case .incomplete:
        matchesSection = installation.state == .incomplete
      case .issues:
        matchesSection = installation.state == .issue
      }

      guard matchesSection, !searchText.isEmpty else { return matchesSection }
      let searchableValues = [
        installation.identity.displayName,
        installation.identity.family ?? "",
        installation.variant.format.rawValue,
        installation.variant.quantization ?? "",
        installation.rootURL.path,
      ]
      return searchableValues.contains { value in
        value.localizedCaseInsensitiveContains(searchText)
      }
    }
  }

  var selectedInstallation: ModelInstallation? {
    guard let selectedInstallationID else { return nil }
    return installations.first { $0.id == selectedInstallationID }
  }

  func setSourceEnabled(_ sourceID: ScanSource.ID, enabled: Bool) {
    guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
    let source = sources[index]
    sources[index] = ScanSource(
      id: source.id,
      displayName: source.displayName,
      providerID: source.providerID,
      rootURL: source.rootURL,
      volumeIdentity: source.volumeIdentity,
      accessState: enabled ? .allowed : .notSetUp,
      isEnabled: enabled
    )
  }

  func addManualFolder() {
    guard let url = folderSelector.chooseFolder() else { return }
    let standardizedURL = url.standardizedFileURL
    let sourceID = "manual:\(standardizedURL.path)"
    guard !sources.contains(where: { $0.id == sourceID }) else { return }
    sources.append(
      ScanSource(
        id: sourceID,
        displayName: standardizedURL.lastPathComponent,
        providerID: .manual,
        rootURL: standardizedURL,
        accessState: .allowed,
        isEnabled: true
      )
    )
  }

  func startScan() {
    guard let coordinator else {
      issues = [
        InventoryIssue(
          id: "CONFIGURATION_INVALID",
          code: "CONFIGURATION_INVALID",
          severity: .blocking,
          sourceID: "application",
          summary: "The adapter registry could not be created."
        )
      ]
      return
    }

    scanTask?.cancel()
    isScanning = true
    let enabledSources = sources.filter(\.isEnabled)
    scanTask = Task {
      let snapshot = await coordinator.scan(sources: enabledSources)
      guard !Task.isCancelled else {
        isScanning = false
        return
      }
      installations = snapshot.installations
      issues = snapshot.issues
      lastScanDate = snapshot.scannedAt
      isScanning = false
      logger.info(
        "Inventory scan completed with \(snapshot.installations.count, privacy: .public) installations"
      )
    }
  }

  func cancelScan() {
    scanTask?.cancel()
    isScanning = false
  }

  func revealSelectedInstallation() {
    guard let selectedInstallation else { return }
    fileRevealer.reveal(selectedInstallation.rootURL)
  }
}

enum InventorySection: String, CaseIterable, Identifiable {
  case all
  case providers
  case incomplete
  case issues

  var id: Self { self }

  var localizedKey: LocalizedStringResource {
    switch self {
    case .all: "sidebar.all-models"
    case .providers: "sidebar.providers"
    case .incomplete: "sidebar.incomplete"
    case .issues: "sidebar.issues"
    }
  }

  var systemImage: String {
    switch self {
    case .all: "square.stack.3d.up"
    case .providers: "shippingbox"
    case .incomplete: "arrow.down.circle.dotted"
    case .issues: "exclamationmark.triangle"
    }
  }
}
