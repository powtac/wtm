import Foundation
import OSLog
import Observation
import WTMDomain
import WTMInventory

struct ActiveScanState {
  let startedAt: Date
  var currentSource: ScanSource?
  var completedSourceCount: Int
  var totalSourceCount: Int
  var discoveredInstallationCount: Int
}

struct ScanCompletionSummary {
  let completedAt: Date
  let scannedSourceCount: Int
  let installationCount: Int
  let allocatedByteCount: Int64
  let issueCount: Int
  let wasCancelled: Bool
}

@MainActor
@Observable
final class InventoryViewModel {
  private(set) var sources: [ScanSource]
  private(set) var installations: [ModelInstallation] = []
  private(set) var issues: [InventoryIssue] = []
  private(set) var lastScanDate: Date?
  private(set) var isScanning = false
  private(set) var isPreparingSources = true
  private(set) var hasCompletedOnboarding = false
  private(set) var activeScan: ActiveScanState?
  private(set) var scanSummary: ScanCompletionSummary?
  private(set) var scanOnLaunch = true
  private(set) var oldModelThresholdDays = 90
  private(set) var mountedVolumes: [MountedVolumeInfo] = []
  var selectedSection = InventorySection.all
  var selectedInstallationID: ModelInstallation.ID?
  var searchText = ""
  var selectedProviderID: ProviderID?
  var selectedFormat: ModelFormat?
  var selectedState: InstallationState?
  var selectedSourceID: ScanSource.ID?

  private let coordinator: InventoryCoordinator?
  private let defaultSources: [ScanSource]
  private let sourceSettingsStore: any SourceSettingsStoring
  private let folderSelector: any FolderSelecting
  private let fileRevealer: any FileRevealing
  private let volumeCatalog: any VolumeCataloging
  private var scanTask: Task<Void, Never>?
  private var didPrepareForLaunch = false
  private var sourceSettingsRevision: UInt64 = 0
  private let logger = Logger(subsystem: "de.powtac.whatthemodel", category: "inventory")

  init(
    coordinator: InventoryCoordinator?,
    initialSources: [ScanSource],
    sourceSettingsStore: any SourceSettingsStoring,
    folderSelector: any FolderSelecting,
    fileRevealer: any FileRevealing,
    volumeCatalog: any VolumeCataloging
  ) {
    self.coordinator = coordinator
    sources = initialSources
    defaultSources = initialSources
    self.sourceSettingsStore = sourceSettingsStore
    self.folderSelector = folderSelector
    self.fileRevealer = fileRevealer
    self.volumeCatalog = volumeCatalog
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
      case .old:
        matchesSection =
          installation.earliestChangeTimestamp.map {
            Date.now.timeIntervalSince($0.value) >= Double(oldModelThresholdDays) * 86_400
          } ?? false
      case .ageUnknown:
        matchesSection = installation.earliestChangeTimestamp == nil
      case .incomplete:
        matchesSection = installation.state == .incomplete
      case .issues:
        matchesSection = installation.state == .issue
      }

      guard matchesSection else { return false }
      guard selectedProviderID == nil || installation.providerID == selectedProviderID else {
        return false
      }
      guard selectedFormat == nil || installation.variant.format == selectedFormat else {
        return false
      }
      guard selectedState == nil || installation.state == selectedState else {
        return false
      }
      guard selectedSourceID == nil || installation.sourceID == selectedSourceID else {
        return false
      }
      guard !searchText.isEmpty else { return true }
      let searchableValues = [
        installation.id,
        installation.identity.id,
        installation.identity.displayName,
        installation.identity.family ?? "",
        installation.variant.id,
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

  var storageBreakdown: InventoryStorageBreakdown {
    InventoryStorageBreakdown(installations: installations)
  }

  var filterProviderIDs: [ProviderID] {
    Array(Set(installations.map(\.providerID))).sorted { left, right in
      left.localizedName.localizedStandardCompare(right.localizedName) == .orderedAscending
    }
  }

  var filterFormats: [ModelFormat] {
    Array(Set(installations.map(\.variant.format))).sorted { left, right in
      left.localizedName.localizedStandardCompare(right.localizedName) == .orderedAscending
    }
  }

  var filterStates: [InstallationState] {
    Array(Set(installations.map(\.state))).sorted { left, right in
      left.localizedName.localizedStandardCompare(right.localizedName) == .orderedAscending
    }
  }

  var filterSources: [ScanSource] {
    let installationSourceIDs = Set(installations.map(\.sourceID))
    return sources.filter { installationSourceIDs.contains($0.id) }
  }

  var availableStorageProviderIDs: [ProviderID] {
    Array(Set(sources.map(\.providerID))).sorted { left, right in
      left.localizedName.localizedStandardCompare(right.localizedName) == .orderedAscending
    }
  }

  var hasActiveInventoryFilter: Bool {
    selectedProviderID != nil || selectedFormat != nil || selectedState != nil
      || selectedSourceID != nil
  }

  func clearInventoryFilters() {
    selectedProviderID = nil
    selectedFormat = nil
    selectedState = nil
    selectedSourceID = nil
  }

  var compactCurrentScanPath: String? {
    guard let url = activeScan?.currentSource?.rootURL else { return nil }
    let path = url.standardizedFileURL.path
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
    return "~" + path.dropFirst(homePath.count)
  }

  func prepareForLaunch() async {
    guard !didPrepareForLaunch else { return }
    didPrepareForLaunch = true

    do {
      if let snapshot = try await sourceSettingsStore.load() {
        sourceSettingsRevision = snapshot.revision
        sources = mergeStoredSources(snapshot.sources)
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        scanOnLaunch = snapshot.scanOnLaunch
        oldModelThresholdDays = snapshot.oldModelThresholdDays
      }
    } catch {
      reportSettingsIssue(code: "SOURCE_SETTINGS_LOAD_FAILED")
    }

    refreshSourceAccess()
    isPreparingSources = false
    if hasCompletedOnboarding, scanOnLaunch, sources.contains(where: \.isEnabled) {
      startScan()
    }
  }

  func setSourceEnabled(_ sourceID: ScanSource.ID, enabled: Bool) {
    guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
    let source = sources[index]
    let updated = ScanSource(
      id: source.id,
      displayName: source.displayName,
      providerID: source.providerID,
      rootURL: source.rootURL,
      volumeIdentity: source.volumeIdentity,
      accessState: enabled ? .allowed : .notSetUp,
      isEnabled: enabled
    )
    sources[index] = refreshedSource(updated)
    persistSourceSettings()
  }

  func addManualFolder(startingAt url: URL? = nil) {
    guard let url = folderSelector.chooseFolder(startingAt: url) else { return }
    let settingsStore = sourceSettingsStore
    Task { [weak self, settingsStore] in
      let source = await settingsStore.makeManualSource(for: url)
      guard let self,
        !self.sources.contains(where: {
          $0.rootURL.standardizedFileURL == source.rootURL.standardizedFileURL
        })
      else { return }
      self.sources.append(source)
      self.persistSourceSettings()
    }
  }

  func grantAccessAgain(to sourceID: ScanSource.ID) {
    guard let source = sources.first(where: { $0.id == sourceID }) else { return }
    guard let url = folderSelector.chooseFolder(startingAt: source.rootURL) else { return }
    let settingsStore = sourceSettingsStore
    Task { [weak self, settingsStore] in
      let replacement = await settingsStore.replace(source, with: url)
      guard let self, let index = self.sources.firstIndex(where: { $0.id == sourceID }) else {
        return
      }
      self.sources[index] = self.refreshedSource(replacement)
      self.persistSourceSettings()
    }
  }

  func revokeSource(_ sourceID: ScanSource.ID) {
    if isScanning { cancelScan() }
    installations.removeAll { $0.sourceID == sourceID }
    issues.removeAll { $0.sourceID == sourceID }
    if selectedInstallation?.sourceID == sourceID { selectedInstallationID = nil }

    if let builtIn = defaultSources.first(where: { $0.id == sourceID }),
      let index = sources.firstIndex(where: { $0.id == sourceID })
    {
      sources[index] = builtIn
    } else {
      sources.removeAll { $0.id == sourceID }
    }
    persistSourceSettings()
  }

  func refreshMountedVolumes() {
    refreshSourceAccess()
  }

  func handleVolumeChange() {
    let priorStates = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0.accessState) })
    refreshSourceAccess()
    let newlyOffline = Set(
      sources.filter { source in
        source.isEnabled && source.accessState == .offline
          && priorStates[source.id] != .offline
      }.map(\.id)
    )
    let newlyAvailable = Set(
      sources.filter { source in
        source.isEnabled && source.accessState == .allowed
          && priorStates[source.id] == .offline
      }.map(\.id)
    )

    if !newlyOffline.isEmpty {
      if let activeSourceID = activeScan?.currentSource?.id,
        newlyOffline.contains(activeSourceID)
      {
        cancelScan()
      }
      installations.removeAll { newlyOffline.contains($0.sourceID) }
      issues.removeAll { newlyOffline.contains($0.sourceID) }
    }
    if !newlyAvailable.isEmpty, !isScanning {
      startScan(sourceIDs: newlyAvailable)
    }
  }

  func setScanOnLaunch(_ enabled: Bool) {
    scanOnLaunch = enabled
    persistSourceSettings()
  }

  func setOldModelThresholdDays(_ days: Int) {
    oldModelThresholdDays = min(max(days, 1), 3_650)
    persistSourceSettings()
  }

  func completeOnboardingAndStartScan() {
    guard sources.contains(where: \.isEnabled) else { return }
    hasCompletedOnboarding = true
    persistSourceSettings()
    startScan()
  }

  func startScan() {
    startScan(sourceIDs: nil)
  }

  private func startScan(sourceIDs: Set<ScanSource.ID>?) {
    guard !isScanning else { return }
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

    refreshSourceAccess()
    let enabledSources = sources.filter { source in
      source.isEnabled && (sourceIDs == nil || sourceIDs?.contains(source.id) == true)
    }
    guard !enabledSources.isEmpty else { return }

    if let sourceIDs {
      installations.removeAll { sourceIDs.contains($0.sourceID) }
      issues.removeAll { sourceIDs.contains($0.sourceID) }
      if let selectedInstallationID,
        !installations.contains(where: { $0.id == selectedInstallationID })
      {
        self.selectedInstallationID = nil
      }
    } else {
      installations = []
      issues = []
      selectedInstallationID = nil
    }
    scanSummary = nil
    isScanning = true
    activeScan = ActiveScanState(
      startedAt: .now,
      currentSource: nil,
      completedSourceCount: 0,
      totalSourceCount: enabledSources.count,
      discoveredInstallationCount: 0
    )
    let stream = coordinator.scanEvents(sources: enabledSources)
    scanTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.isScanning {
          self.finishScan(wasCancelled: true, completedAt: .now)
        }
      }

      for await event in stream {
        guard !Task.isCancelled else { return }
        self.consume(event)
      }
    }
  }

  func cancelScan() {
    guard isScanning else { return }
    scanTask?.cancel()
    scanTask = nil
    finishScan(wasCancelled: true, completedAt: .now)
  }

  func revealSelectedInstallation() {
    guard let selectedInstallation else { return }
    fileRevealer.reveal(selectedInstallation.rootURL)
  }

  func reveal(_ url: URL) {
    fileRevealer.reveal(url)
  }

  private func consume(_ event: InventoryScanEvent) {
    switch event {
    case .started(let sourceCount, let startedAt):
      activeScan = ActiveScanState(
        startedAt: startedAt,
        currentSource: nil,
        completedSourceCount: 0,
        totalSourceCount: sourceCount,
        discoveredInstallationCount: 0
      )
    case .sourceStarted(let source, _, _):
      activeScan?.currentSource = source
    case .batch(_, let newInstallations, let newIssues):
      mergeInstallations(newInstallations)
      mergeIssues(newIssues)
      activeScan?.discoveredInstallationCount = installations.count
    case .sourceFinished(_, let completed, let total):
      activeScan?.completedSourceCount = completed
      activeScan?.totalSourceCount = total
    case .finished(let scannedSourceIDs, let scannedAt):
      lastScanDate = scannedAt
      finishScan(
        wasCancelled: false,
        completedAt: scannedAt,
        scannedSourceCount: scannedSourceIDs.count
      )
      logger.info(
        "Inventory scan completed with \(self.installations.count, privacy: .public) installations"
      )
    }
  }

  private func mergeInstallations(_ newInstallations: [ModelInstallation]) {
    for installation in newInstallations {
      if let index = installations.firstIndex(where: { $0.id == installation.id }) {
        installations[index] = installation
      } else {
        installations.append(installation)
      }
    }
  }

  private func mergeIssues(_ newIssues: [InventoryIssue]) {
    for issue in newIssues {
      if let index = issues.firstIndex(where: { $0.id == issue.id }) {
        issues[index] = issue
      } else {
        issues.append(issue)
      }
    }
  }

  private func finishScan(
    wasCancelled: Bool,
    completedAt: Date,
    scannedSourceCount: Int? = nil
  ) {
    let completedSources = scannedSourceCount ?? activeScan?.completedSourceCount ?? 0
    scanSummary = ScanCompletionSummary(
      completedAt: completedAt,
      scannedSourceCount: completedSources,
      installationCount: installations.count,
      allocatedByteCount: InventorySnapshot(
        installations: installations,
        issues: [],
        scannedSourceIDs: []
      ).uniqueAllocatedByteCount,
      issueCount: issues.count,
      wasCancelled: wasCancelled
    )
    activeScan = nil
    isScanning = false
  }

  private func mergeStoredSources(_ storedSources: [ScanSource]) -> [ScanSource] {
    var merged = storedSources
    let storedIDs = Set(storedSources.map(\.id))
    merged.append(contentsOf: defaultSources.filter { !storedIDs.contains($0.id) })
    return merged
  }

  private func refreshSourceAccess() {
    mountedVolumes = volumeCatalog.mountedVolumes()
    sources = sources.map(refreshedSource)
  }

  private func refreshedSource(_ source: ScanSource) -> ScanSource {
    guard source.isEnabled else {
      return source.replacing(accessState: .notSetUp)
    }
    guard source.accessState != .stale else { return source }

    var rootURL = source.rootURL.standardizedFileURL
    if let volumeIdentity = source.volumeIdentity {
      guard let volume = mountedVolumes.first(where: { $0.id == volumeIdentity.identifier }) else {
        return source.replacing(accessState: .offline)
      }
      rootURL =
        volume.rootURL.appending(
          path: volumeIdentity.relativePath,
          directoryHint: .isDirectory
        ).standardizedFileURL
    }

    guard FileManager.default.fileExists(atPath: rootURL.path) else {
      return source.replacing(rootURL: rootURL, accessState: .offline)
    }
    guard FileManager.default.isReadableFile(atPath: rootURL.path) else {
      return source.replacing(rootURL: rootURL, accessState: .denied)
    }
    return source.replacing(rootURL: rootURL, accessState: .allowed)
  }

  private func persistSourceSettings() {
    sourceSettingsRevision += 1
    let snapshot = SourceSettingsSnapshot(
      revision: sourceSettingsRevision,
      sources: sources,
      hasCompletedOnboarding: hasCompletedOnboarding,
      scanOnLaunch: scanOnLaunch,
      oldModelThresholdDays: oldModelThresholdDays
    )
    let settingsStore = sourceSettingsStore
    Task { [weak self, settingsStore] in
      do {
        try await settingsStore.save(snapshot)
      } catch {
        self?.reportSettingsIssue(code: "SOURCE_SETTINGS_SAVE_FAILED")
      }
    }
  }

  private func reportSettingsIssue(code: String) {
    mergeIssues([
      InventoryIssue(
        id: code,
        code: code,
        severity: .error,
        sourceID: "application",
        summary: "Source settings could not be read or saved."
      )
    ])
  }
}

enum InventorySection: String, CaseIterable, Identifiable {
  case all
  case providers
  case old
  case ageUnknown
  case incomplete
  case issues

  var id: Self { self }

  var localizedKey: LocalizedStringResource {
    switch self {
    case .all: "sidebar.all-models"
    case .providers: "sidebar.providers"
    case .old: "sidebar.old"
    case .ageUnknown: "sidebar.age-unknown"
    case .incomplete: "sidebar.incomplete"
    case .issues: "sidebar.issues"
    }
  }

  var systemImage: String {
    switch self {
    case .all: "square.stack.3d.up"
    case .providers: "shippingbox"
    case .old: "clock.badge.exclamationmark"
    case .ageUnknown: "clock.badge.questionmark"
    case .incomplete: "arrow.down.circle.dotted"
    case .issues: "exclamationmark.triangle"
    }
  }
}

private extension ScanSource {
  func replacing(
    rootURL: URL? = nil,
    accessState: SourceAccessState
  ) -> ScanSource {
    ScanSource(
      id: id,
      displayName: displayName,
      providerID: providerID,
      rootURL: rootURL ?? self.rootURL,
      volumeIdentity: volumeIdentity,
      accessState: accessState,
      isEnabled: isEnabled
    )
  }
}
