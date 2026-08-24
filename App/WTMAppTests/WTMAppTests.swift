import ActionManual
import Foundation
import Testing
import WTMActions
import WTMAdapterContracts
import WTMDomain
import WTMInventory
import WTMPersistence

@testable import WTM

@MainActor
@Test("Built-in sources require explicit consent")
func builtInSourcesAreDisabled() {
  let model = AppComposition.makeInventoryViewModel()

  #expect(model.sources.allSatisfy { !$0.isEnabled })
}

@MainActor
@Test("Known inventory values use product strings")
func inventoryValuesUseProductStrings() {
  #expect(ProviderID.huggingFace.localizedName == "Hugging Face")
  #expect(InstallationState.incomplete.localizedName == "Incomplete")
}

@Test("The app declares no microphone or media permissions")
func appDeclaresNoMicrophoneOrMediaPermissions() {
  let forbiddenUsageDescriptionKeys = [
    "NSMicrophoneUsageDescription",
    "NSAppleMusicUsageDescription",
    "NSSpeechRecognitionUsageDescription",
  ]

  #expect(
    forbiddenUsageDescriptionKeys.allSatisfy {
      Bundle.main.object(forInfoDictionaryKey: $0) == nil
    }
  )
}

@MainActor
@Test("A stored runtime override suppresses the discovered default after relaunch")
func storedRuntimeOverrideSuppressesDefault() async {
  let stored = ToolDefinition(
    id: UUID(),
    displayName: "Imported llama.cpp",
    role: .runtime,
    runtimeAdapterID: .llamaCpp,
    origin: .imported,
    isEnabled: false,
    executableURL: URL(filePath: "/usr/bin/true"),
    arguments: [.placeholder(.modelPath)],
    supportedFormats: [.gguf]
  )
  let discovered = ToolDefinition(
    id: UUID(),
    displayName: "Discovered llama.cpp",
    role: .runtime,
    runtimeAdapterID: .llamaCpp,
    origin: .builtIn,
    isEnabled: false,
    executableURL: URL(filePath: "/usr/bin/false"),
    arguments: [.placeholder(.modelPath)],
    supportedFormats: [.gguf]
  )
  let model = InventoryViewModel(
    coordinator: nil,
    initialSources: [],
    sourceSettingsStore: FixtureSourceSettingsStore(
      snapshot: SourceSettingsSnapshot(
        revision: 1,
        sources: [],
        hasCompletedOnboarding: true,
        scanOnLaunch: false
      )
    ),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog(),
    toolSettingsStore: FixtureToolSettingsStore(
      snapshot: ToolSettingsSnapshot(revision: 1, definitions: [stored], approvals: [])
    ),
    initialToolDefinitions: [discovered]
  )

  await model.prepareForLaunch()

  #expect(model.toolDefinitions == [stored])
}

@MainActor
@Test("Launch at login remains independent and uses the injected system service")
func launchAtLoginUsesSystemService() {
  let manager = FixtureLaunchAtLoginManager()
  let model = InventoryViewModel(
    coordinator: nil,
    initialSources: [],
    sourceSettingsStore: FixtureSourceSettingsStore(snapshot: nil),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog(),
    launchAtLoginManager: manager
  )

  #expect(!model.isLaunchAtLoginEnabled)
  model.setLaunchAtLogin(true)
  #expect(model.isLaunchAtLoginEnabled)
  #expect(manager.isEnabled)
  model.setLaunchAtLogin(false)
  #expect(!model.isLaunchAtLoginEnabled)
  #expect(!manager.isEnabled)
}

@MainActor
@Test("Artifact headings include zero, singular, and plural counts")
func artifactHeadingsIncludeCounts() {
  #expect(artifactSectionTitle(count: 0) == "0 Artifacts")
  #expect(artifactSectionTitle(count: 1) == "1 Artifact")
  #expect(artifactSectionTitle(count: 9) == "9 Artifacts")
}

@Test("Artifacts use Finder-like alphabetical ordering")
func artifactsUseAlphabeticalOrdering() {
  let artifacts = ["model10.gguf", "zeta.json", "model2.gguf", "Alpha.json"].map { name in
    Artifact(
      id: name,
      url: URL(filePath: "/tmp/\(name)"),
      kind: .metadata,
      logicalByteCount: 1,
      allocatedByteCount: 1
    )
  }

  #expect(
    artifactsSortedByName(artifacts).map(\.url.lastPathComponent)
      == ["Alpha.json", "model2.gguf", "model10.gguf", "zeta.json"]
  )
}

@Test("Inventory rows support ascending and descending column sorting")
func inventoryRowsSupportColumnSorting() {
  let installations = ["Zeta", "Alpha"].map { name in
    let identity = ModelIdentity(id: name, displayName: name)
    let variant = ModelVariant(id: "\(name):variant", identityID: identity.id, format: .gguf)
    return ModelInstallation(
      id: name,
      identity: identity,
      variant: variant,
      sourceID: "source",
      providerID: .manual,
      rootURL: URL(filePath: "/tmp/\(name)"),
      state: .stored,
      artifacts: []
    )
  }

  let ascending = [
    KeyPathComparator(\ModelInstallation.inventorySortName, order: .forward)
  ]
  let descending = [
    KeyPathComparator(\ModelInstallation.inventorySortName, order: .reverse)
  ]
  #expect(installations.sorted(using: ascending).map(\.identity.displayName) == ["Alpha", "Zeta"])
  #expect(installations.sorted(using: descending).map(\.identity.displayName) == ["Zeta", "Alpha"])
}

@Test("Inventory copy representations preserve model identity and absolute paths")
func inventoryCopyRepresentations() {
  let huggingFaceIdentity = ModelIdentity(
    id: "hf:openai/gpt-oss-20b",
    displayName: "gpt-oss-20b",
    family: "openai/gpt-oss-20b"
  )
  let manualIdentity = ModelIdentity(id: "manual:local-model", displayName: "Local Model")
  let installations = [
    ModelInstallation(
      id: "hf",
      identity: huggingFaceIdentity,
      variant: ModelVariant(
        id: "hf:variant",
        identityID: huggingFaceIdentity.id,
        format: .safetensors
      ),
      sourceID: "hugging-face",
      providerID: .huggingFace,
      rootURL: URL(filePath: "/tmp/hugging-face/gpt-oss-20b"),
      state: .stored,
      artifacts: [],
      modelCard: ModelCardLink(
        url: URL(string: "https://huggingface.co/openai/gpt-oss-20b")!,
        confidence: .confirmed,
        evidence: "fixture"
      )
    ),
    ModelInstallation(
      id: "manual",
      identity: manualIdentity,
      variant: ModelVariant(
        id: "manual:variant",
        identityID: manualIdentity.id,
        format: .gguf
      ),
      sourceID: "manual",
      providerID: .manual,
      rootURL: URL(filePath: "/tmp/models/../models/Local Model.gguf"),
      state: .stored,
      artifacts: []
    ),
  ]

  #expect(
    inventoryCopyText(for: installations, representation: .modelName)
      == "gpt-oss-20b\nLocal Model"
  )
  #expect(
    inventoryCopyText(for: installations, representation: .providerAndModelName)
      == "openai/gpt-oss-20b\nmanual/Local Model"
  )
  #expect(
    inventoryCopyText(for: installations, representation: .absoluteModelPath)
      == "/tmp/hugging-face/gpt-oss-20b\n/tmp/models/Local Model.gguf"
  )
}

@Test("Inventory column widths use cell content and ignore headers")
func inventoryColumnWidthsUseCellContent() {
  let names = ["M", "A substantially wider model"]
  let rows = names.map { name in
    let identity = ModelIdentity(id: name, displayName: name)
    let variant = ModelVariant(id: "\(name):variant", identityID: identity.id, format: .gguf)
    let installation = ModelInstallation(
      id: name,
      identity: identity,
      variant: variant,
      sourceID: "s",
      providerID: .manual,
      rootURL: URL(filePath: "/tmp/\(name)"),
      state: .stored,
      artifacts: []
    )
    return InventoryTableRow(
      installation: installation,
      displayedByteCount: 0,
      reclaimableByteCount: 0
    )
  }

  let widths = inventoryTableColumnWidths(
    rows: rows,
    mode: .absolute,
    totalByteCount: 0,
    sourceName: { _ in "S" },
    measureText: { CGFloat($0.count) }
  )

  #expect(widths.name == CGFloat("A substantially wider model".count + 16))
  #expect(widths.reclaimableSize == InventoryTableColumnWidths.minimum)
  #expect(widths.reclaimableSize < CGFloat("Reclaimable".count + 16))
}

@Test("Allocated sizes are rounded to whole display units")
func allocatedSizesUseWholeUnits() {
  let value = wholeByteCount(1_490_000_000, locale: Locale(identifier: "en_US"))

  #expect(value == "1 GB")
  #expect(!value.contains("."))
}

@Test("Model ages use whole hours and days and keep unknown explicit")
func modelAgesUseWholeUnits() {
  let referenceDate = Date(timeIntervalSince1970: 20_000_000)
  let fourHoursOld = ageFixture(
    timestamp: referenceDate.addingTimeInterval(-(4 * 3_600 + 59 * 60))
  )
  let ninetyNineDaysOld = ageFixture(
    timestamp: referenceDate.addingTimeInterval(-(99 * 86_400 + 12 * 3_600))
  )

  #expect(
    installationAgeText(
      fourHoursOld,
      relativeTo: referenceDate,
      locale: Locale(identifier: "en_US")
    ) == "4 hours"
  )
  #expect(
    installationAgeText(
      ninetyNineDaysOld,
      relativeTo: referenceDate,
      locale: Locale(identifier: "en_US")
    ) == "99 days"
  )
  #expect(
    installationAgeText(
      ageFixture(timestamp: nil),
      relativeTo: referenceDate,
      locale: Locale(identifier: "en_US")
    ) == "Age Unknown"
  )
}

@Test("Model card links require HTTPS and a host")
func modelCardsRequireHTTPS() {
  let https = ModelCardLink(
    url: URL(string: "https://huggingface.co/acme/model")!,
    confidence: .confirmed,
    evidence: "fixture"
  )
  let http = ModelCardLink(
    url: URL(string: "http://huggingface.co/acme/model")!,
    confidence: .confirmed,
    evidence: "fixture"
  )

  #expect(validatedModelCardURL(https) == https.url)
  #expect(validatedModelCardURL(http) == nil)
}

@Test("Source settings round-trip without persisting inventory results")
func sourceSettingsRoundTrip() async throws {
  let directoryURL = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directoryURL) }

  let settingsURL = directoryURL.appending(path: "source-settings.json")
  let store = JSONSourceSettingsStore(settingsURL: settingsURL)
  let source = ScanSource(
    id: "manual:test",
    displayName: "Test Models",
    providerID: .manual,
    rootURL: directoryURL,
    accessState: .allowed,
    isEnabled: true
  )
  try await store.save(
    SourceSettingsSnapshot(
      revision: 1,
      sources: [source],
      hasCompletedOnboarding: true,
      scanOnLaunch: true,
      oldModelThresholdDays: 180
    )
  )

  let loaded = try #require(try await store.load())
  #expect(loaded.sources.map(\.id) == [source.id])
  #expect(loaded.hasCompletedOnboarding)
  #expect(loaded.scanOnLaunch)
  #expect(loaded.oldModelThresholdDays == 180)
  let payload = try String(contentsOf: settingsURL, encoding: .utf8)
  #expect(!payload.contains("installations"))
  #expect(!payload.contains("artifacts"))
}

@MainActor
@Test("A returning user scans enabled sources on launch")
func returningUserScansOnLaunch() async throws {
  let source = ScanSource(
    id: "launch",
    displayName: "Launch",
    providerID: LaunchFixtureAdapter.providerID,
    rootURL: URL(filePath: "/tmp"),
    accessState: .allowed,
    isEnabled: true
  )
  let registry = try AdapterRegistry(adapters: [LaunchFixtureAdapter()])
  let settingsStore = FixtureSourceSettingsStore(
    snapshot: SourceSettingsSnapshot(
      revision: 1,
      sources: [source],
      hasCompletedOnboarding: true,
      scanOnLaunch: true
    )
  )
  let model = InventoryViewModel(
    coordinator: InventoryCoordinator(registry: registry),
    initialSources: [],
    sourceSettingsStore: settingsStore,
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog()
  )

  await model.prepareForLaunch()
  for _ in 0..<100 where model.lastScanDate == nil {
    try await Task.sleep(for: .milliseconds(10))
  }

  #expect(model.lastScanDate != nil)
  #expect(model.installations.map(\.id) == ["launch:model"])
  #expect(model.scanSummary?.wasCancelled == false)
  #expect(model.scanSummary?.allocatedByteCount == 4_096)
  #expect(model.inventoryEmptyState == nil)
  model.selectedProviderID = .huggingFace
  #expect(model.visibleInstallations.isEmpty)
  #expect(model.inventoryEmptyState == .noMatches)
  model.selectedProviderID = nil
  model.selectedFormat = .safetensors
  #expect(model.visibleInstallations.isEmpty)
  model.selectedFormat = nil
  model.selectedState = .incomplete
  #expect(model.visibleInstallations.isEmpty)
  model.selectedState = nil
  model.selectedSourceID = "another-source"
  #expect(model.visibleInstallations.isEmpty)
  model.clearInventoryFilters()
  model.searchText = "launch:model"
  #expect(model.visibleInstallations.map(\.id) == ["launch:model"])
  model.searchText = ""
  model.selectedSection = .old
  #expect(model.visibleInstallations.map(\.id) == ["launch:model"])
  model.setOldModelThresholdDays(180)
  #expect(model.visibleInstallations.isEmpty)
  #expect(model.inventoryEmptyState == .noMatches)
  model.searchText = "missing"
  model.selectedProviderID = .huggingFace
  model.showAllModels()
  #expect(model.selectedSection == .all)
  #expect(model.searchText.isEmpty)
  #expect(!model.hasActiveInventoryFilter)
  #expect(model.visibleInstallations.map(\.id) == ["launch:model"])
  #expect(model.inventoryEmptyState == nil)
}

@MainActor
@Test("Scan on Launch can be disabled")
func launchScanCanBeDisabled() async throws {
  let source = ScanSource(
    id: "launch-disabled",
    displayName: "Launch Disabled",
    providerID: LaunchFixtureAdapter.providerID,
    rootURL: URL(filePath: "/tmp"),
    accessState: .allowed,
    isEnabled: true
  )
  let registry = try AdapterRegistry(adapters: [LaunchFixtureAdapter()])
  let model = InventoryViewModel(
    coordinator: InventoryCoordinator(registry: registry),
    initialSources: [],
    sourceSettingsStore: FixtureSourceSettingsStore(
      snapshot: SourceSettingsSnapshot(
        revision: 1,
        sources: [source],
        hasCompletedOnboarding: true,
        scanOnLaunch: false
      )
    ),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog()
  )

  await model.prepareForLaunch()
  try await Task.sleep(for: .milliseconds(20))

  #expect(!model.isScanning)
  #expect(model.lastScanDate == nil)
  #expect(model.installations.isEmpty)
  #expect(model.inventoryEmptyState == .noInventory)
}

@MainActor
@Test("Cleanup executes only after preview and triggers a targeted verification scan")
func cleanupRequiresPreviewAndTriggersTargetedVerification() async throws {
  let rootURL = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: rootURL) }
  let modelURL = rootURL.appending(path: "model.gguf")
  try Data("model".utf8).write(to: modelURL)
  let source = ScanSource(
    id: "cleanup-source",
    displayName: "Cleanup Fixture",
    providerID: .manual,
    rootURL: rootURL,
    accessState: .allowed,
    isEnabled: true
  )
  let scanAdapter = FileBackedManualAdapter(modelURL: modelURL)
  let actionExecutor = ActionExecutor(
    registry: try StorageActionAdapterRegistry(adapters: [ManualStorageActionAdapter()]),
    trashMover: RemovingTrashMover(),
    auditStore: InMemoryActionAuditStore()
  )
  let model = InventoryViewModel(
    coordinator: InventoryCoordinator(registry: try AdapterRegistry(adapters: [scanAdapter])),
    initialSources: [source],
    sourceSettingsStore: FixtureSourceSettingsStore(snapshot: nil),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog(),
    actionExecutor: actionExecutor
  )

  model.startScan()
  for _ in 0..<100 where model.isScanning {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(model.installations.map(\.id) == [FileBackedManualAdapter.installationID])

  model.selectedInstallationIDs = [FileBackedManualAdapter.installationID]
  model.prepareDeletion()
  for _ in 0..<100 where model.deletionPlan == nil && model.deletionError == nil {
    try await Task.sleep(for: .milliseconds(5))
  }
  #expect(model.deletionPlan?.operations.count == 1)
  #expect(FileManager.default.fileExists(atPath: modelURL.path))

  model.executeDeletion(confirmedIrreversible: false)
  for _ in 0..<200 where model.isDeleting || model.isScanning || model.deletionReport == nil {
    try await Task.sleep(for: .milliseconds(5))
  }

  #expect(model.deletionReport?.status == .succeeded)
  #expect(!FileManager.default.fileExists(atPath: modelURL.path))
  #expect(model.installations.isEmpty)
  #expect(model.scanSummary?.scannedSourceCount == 1)
  #expect(model.actionAuditEntries.count == 1)
}

@MainActor
@Test("A cancelled scan generation cannot finish its replacement")
func cancelledScanGenerationCannotMutateReplacement() async throws {
  let source = ScanSource(
    id: "generation",
    displayName: "Generation",
    providerID: .manual,
    rootURL: URL(filePath: "/tmp"),
    accessState: .allowed,
    isEnabled: true
  )
  let scanner = ControlledInventoryScanner()
  let model = InventoryViewModel(
    coordinator: scanner,
    initialSources: [source],
    sourceSettingsStore: FixtureSourceSettingsStore(snapshot: nil),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog()
  )

  model.startScan()
  #expect(scanner.streamCount == 1)
  model.cancelScan()
  model.startScan()
  #expect(scanner.streamCount == 2)
  #expect(model.isScanning)

  await Task.yield()
  #expect(model.isScanning)
  #expect(model.scanSummary == nil)

  let completedAt = Date.now
  scanner.yield(
    .finished(scannedSourceIDs: [source.id], scannedAt: completedAt),
    toStreamAt: 1
  )
  scanner.finishStream(at: 1)
  for _ in 0..<100 where model.isScanning {
    try await Task.sleep(for: .milliseconds(5))
  }

  #expect(!model.isScanning)
  #expect(model.lastScanDate == completedAt)
  #expect(model.scanSummary?.wasCancelled == false)
}

@MainActor
@Test("A stored external source resolves by volume identity after remount")
func externalSourceResolvesAfterRemount() async throws {
  let volumeRoot = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  let modelRoot = volumeRoot.appending(path: "Models", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: volumeRoot) }
  let source = ScanSource(
    id: "external",
    displayName: "External Models",
    providerID: .manual,
    rootURL: URL(filePath: "/Volumes/Disconnected/Models"),
    volumeIdentity: VolumeIdentity(identifier: "volume-1", relativePath: "Models"),
    accessState: .offline,
    isEnabled: true
  )
  let model = InventoryViewModel(
    coordinator: nil,
    initialSources: [],
    sourceSettingsStore: FixtureSourceSettingsStore(
      snapshot: SourceSettingsSnapshot(
        revision: 1,
        sources: [source],
        hasCompletedOnboarding: true,
        scanOnLaunch: false
      )
    ),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: FixedVolumeCatalog(
      volumes: [
        MountedVolumeInfo(
          id: "volume-1",
          name: "External",
          rootURL: volumeRoot,
          totalByteCount: 1_000,
          availableByteCount: 500,
          fileSystem: "APFS",
          isReadOnly: false
        )
      ]
    )
  )

  await model.prepareForLaunch()

  #expect(model.sources.first?.rootURL == modelRoot.standardizedFileURL)
  #expect(model.sources.first?.accessState == .allowed)
}

@MainActor
@Test("Unmount removes external results and remount triggers a targeted scan")
func externalSourceUnmountAndRemountIsTargeted() async throws {
  let volumeRoot = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  let modelRoot = volumeRoot.appending(path: "Models", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: volumeRoot) }

  let source = ScanSource(
    id: "external-targeted",
    displayName: "External Models",
    providerID: LaunchFixtureAdapter.providerID,
    rootURL: modelRoot,
    volumeIdentity: VolumeIdentity(identifier: "volume-targeted", relativePath: "Models"),
    accessState: .allowed,
    isEnabled: true
  )
  let volume = MountedVolumeInfo(
    id: "volume-targeted",
    name: "External",
    rootURL: volumeRoot,
    totalByteCount: 1_000,
    availableByteCount: 500,
    fileSystem: "APFS",
    isReadOnly: false
  )
  let volumeCatalog = MutableVolumeCatalog(volumes: [volume])
  let registry = try AdapterRegistry(adapters: [LaunchFixtureAdapter()])
  let model = InventoryViewModel(
    coordinator: InventoryCoordinator(registry: registry),
    initialSources: [],
    sourceSettingsStore: FixtureSourceSettingsStore(
      snapshot: SourceSettingsSnapshot(
        revision: 1,
        sources: [source],
        hasCompletedOnboarding: true,
        scanOnLaunch: false
      )
    ),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: volumeCatalog
  )

  await model.prepareForLaunch()
  model.startScan()
  for _ in 0..<100 where model.lastScanDate == nil {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(model.installations.map(\.sourceID) == [source.id])

  volumeCatalog.replace(with: [])
  model.handleVolumeChange()
  #expect(model.sources.first?.accessState == .offline)
  #expect(model.installations.isEmpty)

  let firstScanDate = try #require(model.lastScanDate)
  volumeCatalog.replace(with: [volume])
  model.handleVolumeChange()
  for _ in 0..<100 where model.lastScanDate == firstScanDate {
    try await Task.sleep(for: .milliseconds(10))
  }

  #expect(model.sources.first?.accessState == .allowed)
  #expect(model.sources.first?.rootURL == modelRoot.standardizedFileURL)
  #expect(model.installations.map(\.sourceID) == [source.id])
  #expect(model.lastScanDate != firstScanDate)
}

@MainActor
@Test("Denied access can be granted again and a source can be revoked")
func sourceAccessCanRecoverAndBeRevoked() async throws {
  let replacementURL = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(at: replacementURL, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: replacementURL) }
  let source = ScanSource(
    id: "manual:recover",
    displayName: "Recover",
    providerID: .manual,
    rootURL: URL(filePath: "/missing"),
    accessState: .denied,
    isEnabled: true
  )
  let model = InventoryViewModel(
    coordinator: nil,
    initialSources: [],
    sourceSettingsStore: FixtureSourceSettingsStore(
      snapshot: SourceSettingsSnapshot(
        revision: 1,
        sources: [source],
        hasCompletedOnboarding: true,
        scanOnLaunch: false
      )
    ),
    folderSelector: FixedFolderSelector(url: replacementURL),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog()
  )
  await model.prepareForLaunch()

  model.grantAccessAgain(to: source.id)
  for _ in 0..<100 where model.sources.first?.rootURL != replacementURL {
    try await Task.sleep(for: .milliseconds(5))
  }

  #expect(model.sources.first?.rootURL == replacementURL)
  #expect(model.sources.first?.accessState == .allowed)
  model.revokeSource(source.id)
  #expect(model.sources.isEmpty)
}

private actor FixtureSourceSettingsStore: SourceSettingsStoring {
  private let snapshot: SourceSettingsSnapshot?

  init(snapshot: SourceSettingsSnapshot?) {
    self.snapshot = snapshot
  }

  func load() -> SourceSettingsSnapshot? {
    snapshot
  }

  func save(_: SourceSettingsSnapshot) {}

  func makeManualSource(for url: URL) -> ScanSource {
    ScanSource(
      id: "manual:test",
      displayName: url.lastPathComponent,
      providerID: .manual,
      rootURL: url,
      accessState: .allowed,
      isEnabled: true
    )
  }

  func replace(_ source: ScanSource, with url: URL) -> ScanSource {
    ScanSource(
      id: source.id,
      displayName: source.displayName,
      providerID: source.providerID,
      rootURL: url,
      accessState: .allowed,
      isEnabled: true
    )
  }
}

private actor FixtureToolSettingsStore: ToolSettingsStoring {
  private let snapshot: ToolSettingsSnapshot?

  init(snapshot: ToolSettingsSnapshot?) {
    self.snapshot = snapshot
  }

  func load() -> ToolSettingsSnapshot? { snapshot }
  func save(_: ToolSettingsSnapshot) {}
}

private struct LaunchFixtureAdapter: StorageProviderAdapter {
  static let providerID = ProviderID(rawValue: "launch-fixture")
  let id = providerID
  let displayName = "Launch Fixture"

  func scan(source: ScanSource) async -> AdapterScanResult {
    let identity = ModelIdentity(id: "launch", displayName: "Launch Model")
    let variant = ModelVariant(id: "launch:variant", identityID: identity.id, format: .gguf)
    let installation = ModelInstallation(
      id: "launch:model",
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: source.rootURL,
      state: .stored,
      artifacts: [
        Artifact(
          id: "launch:artifact",
          url: source.rootURL.appending(path: "model.gguf"),
          kind: .weights,
          logicalByteCount: 4_096,
          allocatedByteCount: 4_096,
          physicalIdentifier: "launch:artifact"
        )
      ],
      timestamps: [
        ObservedTimestamp(
          value: Date.now.addingTimeInterval(-(100 * 86_400)),
          kind: .fileCreation,
          confidence: .derived
        )
      ]
    )
    return AdapterScanResult(source: source, installations: [installation])
  }
}

private struct FileBackedManualAdapter: StorageProviderAdapter {
  static let installationID = "manual:cleanup-fixture"
  let id = ProviderID.manual
  let displayName = "File-backed Manual Fixture"
  let modelURL: URL

  func scan(source: ScanSource) async -> AdapterScanResult {
    guard FileManager.default.fileExists(atPath: modelURL.path) else {
      return AdapterScanResult(source: source, installations: [])
    }
    let identity = ModelIdentity(id: Self.installationID, displayName: "Cleanup Fixture")
    let variant = ModelVariant(
      id: "\(Self.installationID):variant",
      identityID: identity.id,
      format: .gguf
    )
    let installation = ModelInstallation(
      id: Self.installationID,
      identity: identity,
      variant: variant,
      sourceID: source.id,
      providerID: id,
      rootURL: source.rootURL,
      state: .stored,
      artifacts: [
        Artifact(
          id: "cleanup-artifact",
          url: modelURL,
          kind: .weights,
          logicalByteCount: 5,
          allocatedByteCount: 4_096,
          physicalIdentifier: "cleanup-artifact"
        )
      ]
    )
    return AdapterScanResult(source: source, installations: [installation])
  }
}

private actor RemovingTrashMover: TrashMoving {
  func moveToTrash(_ url: URL) throws {
    try FileManager.default.removeItem(at: url)
  }
}

private func ageFixture(timestamp: Date?) -> ModelInstallation {
  let identity = ModelIdentity(id: "age", displayName: "Age Model")
  let variant = ModelVariant(id: "age:variant", identityID: identity.id, format: .gguf)
  return ModelInstallation(
    id: "age:model",
    identity: identity,
    variant: variant,
    sourceID: "source",
    providerID: .manual,
    rootURL: URL(filePath: "/tmp/age-model"),
    state: .stored,
    artifacts: [],
    timestamps: timestamp.map {
      [ObservedTimestamp(value: $0, kind: .fileCreation, confidence: .derived)]
    } ?? []
  )
}

@MainActor
private final class FixtureLaunchAtLoginManager: LaunchAtLoginManaging {
  var isEnabled = false

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
  }
}

@MainActor
private struct NilFolderSelector: FolderSelecting {
  func chooseFolder(startingAt _: URL?) -> URL? { nil }
}

@MainActor
private struct FixedFolderSelector: FolderSelecting {
  let url: URL

  func chooseFolder(startingAt _: URL?) -> URL? { url }
}

@MainActor
private struct NoopFileRevealer: FileRevealing {
  func reveal(_: URL) {}
}

private struct EmptyVolumeCatalog: VolumeCataloging {
  func mountedVolumes() -> [MountedVolumeInfo] { [] }
}

private struct FixedVolumeCatalog: VolumeCataloging {
  let volumes: [MountedVolumeInfo]

  func mountedVolumes() -> [MountedVolumeInfo] { volumes }
}

private final class MutableVolumeCatalog: VolumeCataloging, @unchecked Sendable {
  private let lock = NSLock()
  private var volumes: [MountedVolumeInfo]

  init(volumes: [MountedVolumeInfo]) {
    self.volumes = volumes
  }

  func mountedVolumes() -> [MountedVolumeInfo] {
    lock.withLock { volumes }
  }

  func replace(with volumes: [MountedVolumeInfo]) {
    lock.withLock { self.volumes = volumes }
  }
}

private final class ControlledInventoryScanner: InventoryScanning, @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [AsyncStream<InventoryScanEvent>.Continuation] = []

  var streamCount: Int {
    lock.withLock { continuations.count }
  }

  func scanEvents(sources _: [ScanSource]) -> AsyncStream<InventoryScanEvent> {
    AsyncStream { continuation in
      lock.withLock { continuations.append(continuation) }
    }
  }

  func yield(_ event: InventoryScanEvent, toStreamAt index: Int) {
    continuation(at: index)?.yield(event)
  }

  func finishStream(at index: Int) {
    continuation(at: index)?.finish()
  }

  private func continuation(
    at index: Int
  ) -> AsyncStream<InventoryScanEvent>.Continuation? {
    lock.withLock {
      continuations.indices.contains(index) ? continuations[index] : nil
    }
  }
}
