import Foundation
import OSLog
import Observation
import WTMActions
import WTMAdapterContracts
import WTMDomain
import WTMInventory
import WTMPersistence
import WTMRuntime

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

enum InventoryEmptyState: Equatable {
  case scanning
  case noInventory
  case noMatches
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
  private(set) var toolDefinitions: [ToolDefinition] = []
  private(set) var toolApprovals: [ToolDefinition.ID: ToolExecutionApproval] = [:]
  private(set) var runtimeReadiness: [RuntimeReadinessKey: RuntimeReadiness] = [:]
  private(set) var runtimeSessions: [RuntimeInstance.ID: RuntimeSessionSnapshot] = [:]
  private(set) var runtimePlanPreview: RuntimePlanPreview?
  private(set) var toolImportPreview: ToolDefinitionImportPreview?
  private(set) var runtimeError: RuntimeUIError?
  private(set) var clientPlanPreview: ClientPlanPreview?
  private(set) var clientError: ClientUIError?
  private(set) var clientSessions: [UUID: ClientHandoffSnapshot] = [:]
  private(set) var isLaunchAtLoginEnabled = false
  private(set) var launchAtLoginError: String?
  private(set) var isCheckingRuntime = false
  private(set) var isPreparingRuntime = false
  private(set) var isRunningRuntimeAction = false
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
  private let registeredStorageProviderIDs: Set<ProviderID>
  private let folderSelector: any FolderSelecting
  private let fileRevealer: any FileRevealing
  private let volumeCatalog: any VolumeCataloging
  private let actionExecutor: ActionExecutor?
  private let runtimeRegistry: RuntimeAdapterRegistry?
  private let runtimeBroker: RuntimeBroker?
  private let clientRegistry: ClientAdapterRegistry?
  private let clientBroker: ClientHandoffBroker?
  private let launchAtLoginManager: (any LaunchAtLoginManaging)?
  private let toolSettingsStore: (any ToolSettingsStoring)?
  private let initialToolDefinitions: [ToolDefinition]
  private let runtimeToolTemplates: [RuntimeToolTemplate]
  private let executableSelector: (any ExecutableSelecting)?
  private let toolManifestDocument: (any ToolManifestDocumenting)?
  private let invocationBuilder: ToolInvocationBuilder
  private var scanTask: Task<Void, Never>?
  private var actionTask: Task<Void, Never>?
  private var runtimeTask: Task<Void, Never>?
  private var clientTask: Task<Void, Never>?
  private var activeScanGenerationID: UUID?
  private var didPrepareForLaunch = false
  private var sourceSettingsRevision: UInt64 = 0
  private var toolSettingsRevision: UInt64 = 0
  private let logger = Logger(subsystem: "de.powtac.whatthemodel", category: "inventory")

  init(
    coordinator: (any InventoryScanning)?,
    initialSources: [ScanSource],
    sourceSettingsStore: any SourceSettingsStoring,
    registeredStorageProviderIDs: Set<ProviderID> = [],
    folderSelector: any FolderSelecting,
    fileRevealer: any FileRevealing,
    volumeCatalog: any VolumeCataloging,
    actionExecutor: ActionExecutor? = nil,
    runtimeRegistry: RuntimeAdapterRegistry? = nil,
    runtimeBroker: RuntimeBroker? = nil,
    clientRegistry: ClientAdapterRegistry? = nil,
    clientBroker: ClientHandoffBroker? = nil,
    launchAtLoginManager: (any LaunchAtLoginManaging)? = nil,
    toolSettingsStore: (any ToolSettingsStoring)? = nil,
    initialToolDefinitions: [ToolDefinition] = [],
    runtimeToolTemplates: [RuntimeToolTemplate] = [],
    executableSelector: (any ExecutableSelecting)? = nil,
    toolManifestDocument: (any ToolManifestDocumenting)? = nil,
    invocationBuilder: ToolInvocationBuilder = ToolInvocationBuilder()
  ) {
    self.coordinator = coordinator
    sources = initialSources
    defaultSources = initialSources
    self.sourceSettingsStore = sourceSettingsStore
    self.registeredStorageProviderIDs = registeredStorageProviderIDs
    self.folderSelector = folderSelector
    self.fileRevealer = fileRevealer
    self.volumeCatalog = volumeCatalog
    self.actionExecutor = actionExecutor
    self.runtimeRegistry = runtimeRegistry
    self.runtimeBroker = runtimeBroker
    self.clientRegistry = clientRegistry
    self.clientBroker = clientBroker
    self.launchAtLoginManager = launchAtLoginManager
    self.toolSettingsStore = toolSettingsStore
    self.initialToolDefinitions = initialToolDefinitions
    self.runtimeToolTemplates = runtimeToolTemplates
    self.executableSelector = executableSelector
    self.toolManifestDocument = toolManifestDocument
    self.invocationBuilder = invocationBuilder
    toolDefinitions = initialToolDefinitions
    isLaunchAtLoginEnabled = launchAtLoginManager?.isEnabled ?? false
  }

  isolated deinit {
    scanTask?.cancel()
    actionTask?.cancel()
    runtimeTask?.cancel()
    clientTask?.cancel()
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
    actionExecutor != nil && !selectedInstallationIDs.isEmpty
      && selectedInstallations.allSatisfy {
        actionExecutor?.supportedProviderIDs.contains($0.providerID) == true
      } && !isScanning
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
    Array(registeredStorageProviderIDs.union(sources.map(\.providerID))).sorted { left, right in
      left.localizedName.localizedStandardCompare(right.localizedName) == .orderedAscending
    }
  }

  var availableClientIDs: [ClientAdapterID] {
    (clientRegistry?.clientIDs ?? []).sorted {
      $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }

  var hasActiveInventoryFilter: Bool {
    selectedProviderID != nil || selectedFormat != nil || selectedState != nil
      || selectedSourceID != nil
  }

  var inventoryEmptyState: InventoryEmptyState? {
    guard selectedSection != .issues, visibleInstallations.isEmpty else { return nil }
    if isScanning, installations.isEmpty { return .scanning }
    return installations.isEmpty ? .noInventory : .noMatches
  }

  func clearInventoryFilters() {
    selectedProviderID = nil
    selectedFormat = nil
    selectedState = nil
    selectedSourceID = nil
  }

  func showAllModels() {
    selectedSection = .all
    searchText = ""
    clearInventoryFilters()
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

    await loadToolSettings()

    refreshSourceAccess()
    refreshActionAudit()
    isPreparingSources = false
    if hasCompletedOnboarding, scanOnLaunch, sources.contains(where: \.isEnabled) {
      startScan()
    }
  }

  func runtimeOptions(for installation: ModelInstallation) -> [RuntimeAdapterID] {
    guard let runtimeRegistry else { return [] }
    return runtimeRegistry.runtimeIDs
      .filter {
        runtimeRegistry.adapter(for: $0)?.supportedFormats.contains(installation.variant.format)
          == true
      }
      .sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
  }

  func readiness(for installation: ModelInstallation, runtimeID: RuntimeAdapterID)
    -> RuntimeReadiness?
  {
    runtimeReadiness[RuntimeReadinessKey(installationID: installation.id, adapterID: runtimeID)]
  }

  func latestRuntimeSession(for installation: ModelInstallation, runtimeID: RuntimeAdapterID)
    -> RuntimeSessionSnapshot?
  {
    runtimeSessions.values
      .filter {
        $0.instance.installationID == installation.id && $0.instance.adapterID == runtimeID
      }
      .sorted { ($0.instance.startedAt ?? .distantPast) > ($1.instance.startedAt ?? .distantPast) }
      .first
  }

  func checkRuntimeReadiness(_ runtimeID: RuntimeAdapterID, for installation: ModelInstallation) {
    guard let adapter = runtimeRegistry?.adapter(for: runtimeID) else {
      runtimeError = .runtimeUnavailable
      return
    }
    isCheckingRuntime = true
    runtimeError = nil
    runtimeTask?.cancel()
    let environment = runtimeEnvironment(for: runtimeID)
    runtimeTask = Task { [weak self, adapter] in
      let readiness = await adapter.readiness(for: installation, environment: environment)
      guard let self, !Task.isCancelled else { return }
      self.runtimeReadiness[
        RuntimeReadinessKey(installationID: installation.id, adapterID: runtimeID)
      ] = readiness
      self.isCheckingRuntime = false
      self.runtimeTask = nil
    }
  }

  func prepareRuntimeTest(_ runtimeID: RuntimeAdapterID, for installation: ModelInstallation) {
    guard let adapter = runtimeRegistry?.adapter(for: runtimeID) else {
      runtimeError = .runtimeUnavailable
      return
    }
    let definition = toolDefinition(for: runtimeID)
    if let definition, !definition.isEnabled {
      runtimeError = .toolDisabled
      return
    }
    isPreparingRuntime = true
    runtimeError = nil
    runtimeTask?.cancel()
    runtimeTask = Task { [weak self, adapter, invocationBuilder] in
      guard let self else { return }
      do {
        var validation: ToolValidationRecord?
        var approval = definition.flatMap { self.toolApprovals[$0.id] }
        var approvalToPersist: ToolExecutionApproval?
        if let definition {
          let currentValidation = try invocationBuilder.inspect(definition)
          validation = currentValidation
          if approval?.matches(definition) != true
            || approval?.executableIdentity != currentValidation.executableIdentity
          {
            let replacement = ToolExecutionApproval(
              definition: definition,
              executableIdentity: currentValidation.executableIdentity,
              approvedAt: .now
            )
            approval = replacement
            approvalToPersist = replacement
          }
        }
        let plan = try await adapter.makeTestPlan(
          for: installation,
          context: RuntimeLaunchContext(
            toolDefinition: definition,
            toolApproval: approval
          )
        )
        guard !Task.isCancelled else { return }
        self.runtimePlanPreview = RuntimePlanPreview(
          installation: installation,
          runtimeName: adapter.displayName,
          plan: plan,
          validation: validation,
          approvalToPersist: approvalToPersist
        )
      } catch let error as ToolInvocationBuilderError {
        self.runtimeError = error == .executableIdentityChanged ? .executableChanged : .toolInvalid
      } catch {
        self.runtimeError = .planFailed
      }
      self.isPreparingRuntime = false
      self.runtimeTask = nil
    }
  }

  func cancelRuntimePreview() {
    runtimePlanPreview = nil
  }

  func executeRuntimeTest() {
    guard let preview = runtimePlanPreview, let runtimeBroker else {
      runtimeError = .runtimeUnavailable
      return
    }
    if let approval = preview.approvalToPersist {
      toolApprovals[approval.definitionID] = approval
      persistToolSettings()
    }
    runtimePlanPreview = nil
    isRunningRuntimeAction = true
    runtimeError = nil
    runtimeTask?.cancel()
    runtimeTask = Task { [weak self, runtimeBroker] in
      do {
        let snapshot = try await runtimeBroker.start(
          plan: preview.plan,
          installation: preview.installation,
          verifyInference: true
        )
        guard let self, !Task.isCancelled else { return }
        self.runtimeSessions[snapshot.instance.id] = snapshot
        self.runtimeReadiness[
          RuntimeReadinessKey(
            installationID: snapshot.instance.installationID,
            adapterID: snapshot.instance.adapterID
          )
        ] = self.readiness(from: snapshot, installation: preview.installation)
      } catch {
        self?.runtimeError = .launchFailed
      }
      self?.isRunningRuntimeAction = false
      self?.runtimeTask = nil
    }
  }

  func refreshRuntimeSession(_ instanceID: RuntimeInstance.ID) {
    guard let runtimeBroker else { return }
    runtimeTask?.cancel()
    runtimeTask = Task { [weak self, runtimeBroker] in
      do {
        let snapshot = try await runtimeBroker.snapshot(for: instanceID)
        self?.runtimeSessions[instanceID] = snapshot
      } catch {
        self?.runtimeError = .runtimeUnavailable
      }
      self?.runtimeTask = nil
    }
  }

  func stopRuntimeSession(_ instanceID: RuntimeInstance.ID) {
    guard let runtimeBroker else { return }
    isRunningRuntimeAction = true
    runtimeError = nil
    runtimeTask?.cancel()
    runtimeTask = Task { [weak self, runtimeBroker] in
      do {
        let snapshot = try await runtimeBroker.stop(instanceID)
        self?.runtimeSessions[instanceID] = snapshot
      } catch {
        self?.runtimeError = .stopFailed
      }
      self?.isRunningRuntimeAction = false
      self?.runtimeTask = nil
    }
  }

  func dismissRuntimeError() {
    runtimeError = nil
  }

  func stopOwnedRuntimeSessionsForTermination() async {
    runtimeTask?.cancel()
    clientTask?.cancel()
    await runtimeBroker?.stopAllOwned()
    await clientBroker?.stopAllOwned()
  }

  func clientOptions(for installation: ModelInstallation) -> [ClientAdapterID] {
    guard let clientRegistry else { return [] }
    return clientRegistry.clientIDs.sorted {
      $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }

  func clientAvailability(
    _ clientID: ClientAdapterID,
    for installation: ModelInstallation
  ) -> ClientAvailability {
    guard let adapter = clientRegistry?.adapter(for: clientID) else {
      return .unavailable(reason: String(localized: "client.error.unavailable"))
    }
    return adapter.availability(for: installation, context: clientContext())
  }

  func prepareClientHandoff(_ clientID: ClientAdapterID, for installation: ModelInstallation) {
    guard let adapter = clientRegistry?.adapter(for: clientID) else {
      clientError = .unavailable
      return
    }
    do {
      let plan = try adapter.makeHandoffPlan(for: installation, context: clientContext())
      clientPlanPreview = ClientPlanPreview(
        installation: installation,
        clientName: adapter.displayName,
        plan: plan
      )
    } catch {
      clientError = .planFailed
    }
  }

  func cancelClientPreview() {
    clientPlanPreview = nil
  }

  func executeClientHandoff() {
    guard let preview = clientPlanPreview, let clientBroker else {
      clientError = .unavailable
      return
    }
    clientPlanPreview = nil
    clientTask?.cancel()
    clientTask = Task { [weak self, clientBroker] in
      do {
        let snapshot = try await clientBroker.start(
          plan: preview.plan,
          installation: preview.installation
        )
        self?.clientSessions[snapshot.id] = snapshot
      } catch {
        self?.clientError = .launchFailed
      }
      self?.clientTask = nil
    }
  }

  func dismissClientError() {
    clientError = nil
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard let launchAtLoginManager else { return }
    do {
      try launchAtLoginManager.setEnabled(enabled)
      isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
      launchAtLoginError = nil
    } catch {
      isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
      launchAtLoginError = String(localized: "settings.login-item.error")
    }
  }

  func dismissLaunchAtLoginError() {
    launchAtLoginError = nil
  }

  private func clientContext() -> ClientHandoffContext {
    ClientHandoffContext(runtimeInstances: runtimeSessions.values.map(\.instance))
  }

  func setToolEnabled(_ definitionID: ToolDefinition.ID, enabled: Bool) {
    guard let definition = toolDefinitions.first(where: { $0.id == definitionID }) else { return }
    if enabled {
      do {
        _ = try invocationBuilder.inspect(definition)
      } catch {
        runtimeError = .toolInvalid
        return
      }
    }
    replaceToolDefinition(copy(definition, isEnabled: enabled))
  }

  func validateTool(_ definitionID: ToolDefinition.ID) {
    guard let definition = toolDefinitions.first(where: { $0.id == definitionID }) else { return }
    do {
      let validation = try invocationBuilder.inspect(definition)
      let updated = copy(definition, lastValidation: validation)
      if let approval = toolApprovals[definition.id],
        approval.executableIdentity != validation.executableIdentity || !approval.matches(updated)
      {
        toolApprovals.removeValue(forKey: definition.id)
      }
      replaceToolDefinition(updated)
    } catch {
      runtimeError = .toolInvalid
    }
  }

  var missingRuntimeToolTemplates: [RuntimeToolTemplate] {
    runtimeToolTemplates.filter { template in
      !toolDefinitions.contains { $0.runtimeAdapterID == template.runtimeAdapterID }
    }
  }

  func chooseRuntimeExecutable(_ runtimeID: RuntimeAdapterID) {
    guard let template = runtimeToolTemplates.first(where: { $0.runtimeAdapterID == runtimeID })
    else { return }
    guard
      let executableURL = executableSelector?.chooseExecutable(
        startingAt: toolDefinition(for: runtimeID)?.executableURL
      )
    else { return }
    let definition = template.makeDefinition(executableURL.standardizedFileURL)
    toolApprovals.removeValue(forKey: definition.id)
    replaceToolDefinition(definition)
    validateTool(definition.id)
  }

  func resetRuntimeTool(_ runtimeID: RuntimeAdapterID) {
    guard let template = runtimeToolTemplates.first(where: { $0.runtimeAdapterID == runtimeID })
    else { return }
    let definitionIDs = Set(
      toolDefinitions.filter { $0.runtimeAdapterID == runtimeID }.map(\.id)
    )
    toolDefinitions.removeAll { definitionIDs.contains($0.id) }
    for definitionID in definitionIDs {
      toolApprovals.removeValue(forKey: definitionID)
    }
    if let defaultDefinition = template.defaultDefinition {
      toolDefinitions.append(defaultDefinition)
    }
    persistToolSettings()
  }

  func revealTool(_ definitionID: ToolDefinition.ID) {
    guard let definition = toolDefinitions.first(where: { $0.id == definitionID }) else { return }
    fileRevealer.reveal(definition.executableURL)
  }

  func importToolDefinition() {
    do {
      guard let imported = try toolManifestDocument?.importDefinition() else { return }
      guard let runtimeID = imported.runtimeAdapterID,
        runtimeRegistry?.adapter(for: runtimeID) != nil,
        runtimeToolTemplates.contains(where: { $0.runtimeAdapterID == runtimeID })
      else {
        runtimeError = .importFailed
        return
      }
      let normalized = ToolDefinitionManifestPolicy.definitionForImport(imported)
      try ToolDefinitionValidator().validate(normalized)
      toolImportPreview = ToolDefinitionImportPreview(definition: normalized)
    } catch {
      runtimeError = .importFailed
    }
  }

  func confirmToolImport() {
    guard let definition = toolImportPreview, let runtimeID = definition.definition.runtimeAdapterID
    else { return }
    let replacedIDs = toolDefinitions.filter { $0.runtimeAdapterID == runtimeID }.map(\.id)
    toolDefinitions.removeAll { $0.runtimeAdapterID == runtimeID }
    for definitionID in replacedIDs {
      toolApprovals.removeValue(forKey: definitionID)
    }
    toolDefinitions.append(definition.definition)
    toolImportPreview = nil
    persistToolSettings()
  }

  func cancelToolImport() {
    toolImportPreview = nil
  }

  func exportToolDefinition(_ definitionID: ToolDefinition.ID) {
    guard let definition = toolDefinitions.first(where: { $0.id == definitionID }) else { return }
    do {
      try toolManifestDocument?.exportDefinition(definition)
    } catch {
      runtimeError = .settingsFailed
    }
  }

  func isToolApproved(_ definition: ToolDefinition) -> Bool {
    guard let approval = toolApprovals[definition.id], approval.matches(definition),
      let validation = try? invocationBuilder.inspect(definition)
    else { return false }
    return approval.executableIdentity == validation.executableIdentity
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
    addFolder(providerID: .manual, startingAt: url)
  }

  func addMLXFolder(startingAt url: URL? = nil) {
    addFolder(providerID: .mlx, startingAt: url)
  }

  private func addFolder(providerID: ProviderID, startingAt url: URL?) {
    guard let url = folderSelector.chooseFolder(startingAt: url) else { return }
    let settingsStore = sourceSettingsStore
    Task { [weak self, settingsStore] in
      let source =
        if providerID == .mlx {
          await settingsStore.makeMLXSource(for: url)
        } else {
          await settingsStore.makeManualSource(for: url)
        }
      guard let self,
        !self.sources.contains(where: {
          $0.providerID == source.providerID
            && $0.rootURL.standardizedFileURL == source.rootURL.standardizedFileURL
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

  private func toolDefinition(for runtimeID: RuntimeAdapterID) -> ToolDefinition? {
    toolDefinitions.first { $0.runtimeAdapterID == runtimeID }
  }

  private func runtimeEnvironment(for runtimeID: RuntimeAdapterID) -> RuntimeEnvironment {
    let definition = toolDefinition(for: runtimeID)
    return RuntimeEnvironment(
      architecture: currentArchitecture,
      memoryCapacityByteCount: Int64(clamping: ProcessInfo.processInfo.physicalMemory),
      toolDefinition: definition,
      toolApproval: definition.flatMap { toolApprovals[$0.id] }
    )
  }

  private var currentArchitecture: String {
    #if arch(arm64)
      "arm64"
    #elseif arch(x86_64)
      "x86_64"
    #else
      "unknown"
    #endif
  }

  private func readiness(
    from snapshot: RuntimeSessionSnapshot,
    installation: ModelInstallation
  ) -> RuntimeReadiness {
    let adapterVersion =
      runtimeRegistry?.adapter(for: snapshot.instance.adapterID)?.version ?? "unknown"
    let checkedAt = snapshot.inference?.checkedAt ?? snapshot.health?.checkedAt ?? .now
    let validation: ModelValidation
    if let inference = snapshot.inference {
      validation = inference.succeeded ? .inferenceVerified : .inferenceFailed
    } else {
      validation = snapshot.health?.succeeded == true ? .runtimeReachable : .blocked
    }
    func observation<Value: Hashable & Codable & Sendable>(
      _ value: Value,
      evidence: String
    ) -> RuntimeObservation<Value> {
      RuntimeObservation(
        value: value,
        adapterID: snapshot.instance.adapterID,
        adapterVersion: adapterVersion,
        checkedAt: checkedAt,
        evidence: evidence
      )
    }
    return RuntimeReadiness(
      installationID: installation.id,
      adapterID: snapshot.instance.adapterID,
      integrity: observation(
        installation.state == .stored ? ModelIntegrity.complete : ModelIntegrity.unknown,
        evidence: "Inventory state"
      ),
      compatibility: observation(.compatible, evidence: "Runtime plan completed"),
      validation: observation(
        validation, evidence: snapshot.inference?.summary ?? snapshot.health?.summary ?? "No probe"),
      runtime: observation(snapshot.instance.state, evidence: "Runtime broker session"),
      estimatedMemory: nil,
      blockers: snapshot.inference?.succeeded == false
        ? [snapshot.inference?.summary ?? "Inference failed"] : []
    )
  }

  private func copy(
    _ definition: ToolDefinition,
    isEnabled: Bool? = nil,
    lastValidation: ToolValidationRecord? = nil
  ) -> ToolDefinition {
    ToolDefinition(
      schemaVersion: definition.schemaVersion,
      id: definition.id,
      displayName: definition.displayName,
      role: definition.role,
      runtimeAdapterID: definition.runtimeAdapterID,
      origin: definition.origin,
      isEnabled: isEnabled ?? definition.isEnabled,
      executableURL: definition.executableURL,
      arguments: definition.arguments,
      supportedFormats: definition.supportedFormats,
      localAPIBaseURL: definition.localAPIBaseURL,
      currentDirectoryURL: definition.currentDirectoryURL,
      environment: definition.environment,
      lastValidation: lastValidation ?? definition.lastValidation
    )
  }

  private func replaceToolDefinition(_ definition: ToolDefinition) {
    if let index = toolDefinitions.firstIndex(where: { $0.id == definition.id }) {
      toolDefinitions[index] = definition
    } else {
      toolDefinitions.append(definition)
    }
    toolDefinitions.sort {
      $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
    persistToolSettings()
  }

  private func loadToolSettings() async {
    guard let toolSettingsStore else { return }
    do {
      guard let snapshot = try await toolSettingsStore.load() else { return }
      toolSettingsRevision = snapshot.revision
      let validator = ToolDefinitionValidator()
      let storedDefinitions = snapshot.definitions.filter {
        (try? validator.validate($0)) != nil
      }
      var merged = storedDefinitions
      let storedIDs = Set(storedDefinitions.map(\.id))
      let storedRuntimeIDs = Set(storedDefinitions.compactMap(\.runtimeAdapterID))
      merged.append(
        contentsOf: initialToolDefinitions.filter { definition in
          guard !storedIDs.contains(definition.id) else { return false }
          guard let runtimeID = definition.runtimeAdapterID else { return true }
          return !storedRuntimeIDs.contains(runtimeID)
        }
      )
      toolDefinitions = merged.sorted {
        $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
      }
      toolApprovals = Dictionary(
        uniqueKeysWithValues: snapshot.approvals.map { ($0.definitionID, $0) }
      )
    } catch {
      runtimeError = .settingsFailed
    }
  }

  private func persistToolSettings() {
    guard let toolSettingsStore else { return }
    toolSettingsRevision += 1
    let snapshot = ToolSettingsSnapshot(
      revision: toolSettingsRevision,
      definitions: toolDefinitions,
      approvals: Array(toolApprovals.values)
    )
    Task { [weak self, toolSettingsStore] in
      do {
        try await toolSettingsStore.save(snapshot)
      } catch {
        self?.runtimeError = .settingsFailed
      }
    }
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
