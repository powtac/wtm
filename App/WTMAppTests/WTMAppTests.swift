import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain
import WTMInventory

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
  model.selectedSection = .old
  #expect(model.visibleInstallations.map(\.id) == ["launch:model"])
  model.setOldModelThresholdDays(180)
  #expect(model.visibleInstallations.isEmpty)
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
