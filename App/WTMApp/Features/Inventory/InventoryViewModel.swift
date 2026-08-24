import Foundation
import OSLog
import Observation
import WTMActions
import WTMAdapterContracts
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
  private(set) var deletionPlan: DeletionPlan?
  private(set) var deletionReport: DeletionExecutionReport?
  private(set) var deletionError: DeletionUIError?
  private(set) var actionAuditEntries: [ActionAuditEntry] = []
  private(set) var isPreparingDeletion = false
  private(set) var isDeleting = false
  var selectedSection = InventorySection.all
  var selectedInstallationIDs: Set<ModelInstallation.ID> = []
  var searchText = ""
  var selectedProviderID: ProviderID?
  var selectedFormat: ModelFormat?
  var selectedState: InstallationState?
  var selectedSourceID: ScanSource.ID?

  private let coordinator: (any InventoryScanning)?
  private let defaultSources: [ScanSource]
  private let sourceSettingsStore: any SourceSettingsStoring
  private let folderSelector: any FolderSelecting
  private let fileRevealer: any FileRevealing
  private let volumeCatalog: any VolumeCataloging
  private let actionExecutor: ActionExecutor?
  private var scanTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?
  private var activeScanGenerationID: UUID?
  private var didPrepareForLaunch = false
  private var sourceSettingsRevision: UInt64 = 0
  private let logger = Logger(subsystem: "de.powtac.whatthemodel", category: "inventory")

  init(
    coordinator: (any InventoryScanning)?,
    initialSources: [ScanSource],
    sourceSettingsStore: any SourceSettingsStoring,
    folderSelector: any FolderSelecting,
    fileRevealer: any FileRevealing,
    volumeCatalog: any VolumeCataloging,
    actionExecutor: ActionExecutor? = nil
  ) {
    self.coordinator = coordinator
    sources = initialSources
    defaultSources = initialSources
    self.sourceSettingsStore = sourceSettingsStore
    self.folderSelector = folderSelector
    self.fileRevealer = fileRevealer
    self.volumeCatalog = volumeCatalog
    self.actionExecutor = actionExecutor
  }

  isolated deinit {
    scanTask?.cancel()
    actionTask?.cancel()
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
    guard selectedInstallationIDs.count == 1,
      let selectedInstallationID = selectedInstallationIDs.first
    else { return nil }
    return installations.first { $0.id == selectedInstallationID }
  }

  var selectedInstallations: [ModelInstallation] {
    installations.filter { selectedInstallationIDs.contains($0.id) }
  }

  var canPrepareDeletion: Bool {
    actionExecutor != nil && !selectedInstallationIDs.isEmpty && !isScanning
      && !isPreparingDeletion && !isDeleting
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
    refreshActionAudit()
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
    let removedInstallationIDs = Set(
      installations.filter { $0.sourceID == sourceID }.map(\.id)
    )
    installations.removeAll { $0.sourceID == sourceID }
    issues.removeAll { $0.sourceID == sourceID }
    selectedInstallationIDs.subtract(removedInstallationIDs)
    invalidateDeletionPreview()

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
      selectedInstallationIDs = selectedInstallationIDs.intersection(Set(installations.map(\.id)))
      invalidateDeletionPreview()
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
    guard !isScanning, !isPreparingDeletion, !isDeleting else { return }
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
      selectedInstallationIDs = selectedInstallationIDs.intersection(Set(installations.map(\.id)))
    } else {
      installations = []
      issues = []
      selectedInstallationIDs = []
    }
    invalidateDeletionPreview()
    scanSummary = nil
    isScanning = true
    let generationID = UUID()
    activeScanGenerationID = generationID
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
        if self.activeScanGenerationID == generationID, self.isScanning {
          self.finishScan(
            wasCancelled: true,
            completedAt: .now,
            generationID: generationID
          )
        }
      }

      for await event in stream {
        guard !Task.isCancelled, self.activeScanGenerationID == generationID else { return }
        self.consume(event, generationID: generationID)
      }
    }
  }

  func cancelScan() {
    guard isScanning else { return }
    activeScanGenerationID = nil
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

  func prepareDeletion() {
    guard canPrepareDeletion, let actionExecutor else { return }
    let requestedIDs = selectedInstallationIDs
    let inventory = installations
    let currentSources = sources
    isPreparingDeletion = true
    deletionError = nil
    deletionReport = nil
    actionTask?.cancel()
    actionTask = Task { [weak self, actionExecutor] in
      do {
        let plan = try await actionExecutor.prepareDeletion(
          installationIDs: requestedIDs,
          currentInventory: inventory,
          sources: currentSources
        )
        guard let self, !Task.isCancelled, self.selectedInstallationIDs == requestedIDs else {
          await actionExecutor.cancel(planID: plan.id)
          return
        }
        self.deletionPlan = plan
      } catch {
        self?.deletionError = DeletionUIError(error)
      }
      self?.isPreparingDeletion = false
      self?.actionTask = nil
    }
  }

  func cancelDeletionPreview() {
    guard let plan = deletionPlan else { return }
    deletionPlan = nil
    Task { [actionExecutor] in await actionExecutor?.cancel(planID: plan.id) }
  }

  func executeDeletion(confirmedIrreversible: Bool) {
    guard let plan = deletionPlan, let actionExecutor, !isDeleting, !isScanning else { return }
    let inventory = installations
    let currentSources = sources
    isDeleting = true
    deletionError = nil
    actionTask?.cancel()
    actionTask = Task { [weak self, actionExecutor] in
      do {
        let report = try await actionExecutor.execute(
          plan,
          currentInventory: inventory,
          sources: currentSources,
          confirmedIrreversible: confirmedIrreversible
        )
        guard let self, !Task.isCancelled else { return }
        self.deletionPlan = nil
        self.deletionReport = report
        self.selectedInstallationIDs = []
        self.isDeleting = false
        self.refreshActionAudit()
        if !report.affectedSourceIDs.isEmpty {
          self.startScan(sourceIDs: report.affectedSourceIDs)
        }
      } catch {
        self?.deletionPlan = nil
        self?.deletionError = DeletionUIError(error)
        self?.isDeleting = false
        self?.refreshActionAudit()
      }
      self?.actionTask = nil
    }
  }

  func dismissDeletionReport() {
    deletionReport = nil
  }

  func dismissDeletionError() {
    deletionError = nil
  }

  func clearActionAudit() {
    guard let actionExecutor else { return }
    Task { [weak self, actionExecutor] in
      do {
        try await actionExecutor.clearAudit()
        self?.actionAuditEntries = []
      } catch {
        self?.deletionError = .auditUnavailable
      }
    }
  }

  private func consume(_ event: InventoryScanEvent, generationID: UUID) {
    guard activeScanGenerationID == generationID else { return }
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
        scannedSourceCount: scannedSourceIDs.count,
        generationID: generationID
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
    scannedSourceCount: Int? = nil,
    generationID: UUID? = nil
  ) {
    if let generationID, activeScanGenerationID != generationID { return }
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
    activeScanGenerationID = nil
    scanTask = nil
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

  private func refreshActionAudit() {
    guard let actionExecutor else { return }
    Task { [weak self, actionExecutor] in
      self?.actionAuditEntries = await actionExecutor.auditEntries()
    }
  }

  private func invalidateDeletionPreview() {
    guard let plan = deletionPlan else { return }
    deletionPlan = nil
    Task { [actionExecutor] in await actionExecutor?.cancel(planID: plan.id) }
  }
}

enum DeletionUIError: String, Identifiable {
  case noSelection
  case adapterUnavailable
  case sourceUnavailable
  case modelInUse
  case providerUnavailable
  case noDeletableArtifacts
  case planExpired
  case planConflict
  case irreversibleConfirmationRequired
  case inventoryChanged
  case revalidationFailed
  case auditUnavailable
  case unknown

  var id: String { rawValue }

  init(_ error: Error) {
    switch error {
    case ActionExecutorError.noSelection:
      self = .noSelection
    case ActionExecutorError.adapterUnavailable:
      self = .adapterUnavailable
    case ActionExecutorError.planExpired:
      self = .planExpired
    case ActionExecutorError.planConflict:
      self = .planConflict
    case ActionExecutorError.irreversibleConfirmationRequired:
      self = .irreversibleConfirmationRequired
    case ActionExecutorError.inventoryChanged, ActionExecutorError.planNotActive:
      self = .inventoryChanged
    case ActionExecutorError.sourceUnavailable:
      self = .sourceUnavailable
    case ActionExecutorError.targetInUse:
      self = .modelInUse
    case ActionExecutorError.targetRevalidationFailed,
      ActionExecutorError.providerRevalidationFailed:
      self = .revalidationFailed
    case StorageActionAdapterError.modelInUse:
      self = .modelInUse
    case StorageActionAdapterError.providerUnavailable:
      self = .providerUnavailable
    case StorageActionAdapterError.noDeletableArtifacts:
      self = .noDeletableArtifacts
    case StorageActionAdapterError.sourceUnavailable:
      self = .sourceUnavailable
    default:
      self = .unknown
    }
  }

  var messageKey: LocalizedStringResource {
    switch self {
    case .noSelection: "deletion.error.no-selection"
    case .adapterUnavailable: "deletion.error.adapter-unavailable"
    case .sourceUnavailable: "deletion.error.source-unavailable"
    case .modelInUse: "deletion.error.model-in-use"
    case .providerUnavailable: "deletion.error.provider-unavailable"
    case .noDeletableArtifacts: "deletion.error.no-artifacts"
    case .planExpired: "deletion.error.plan-expired"
    case .planConflict: "deletion.error.conflict"
    case .irreversibleConfirmationRequired: "deletion.error.confirmation-required"
    case .inventoryChanged: "deletion.error.inventory-changed"
    case .revalidationFailed: "deletion.error.revalidation-failed"
    case .auditUnavailable: "deletion.error.audit-unavailable"
    case .unknown: "deletion.error.unknown"
    }
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
