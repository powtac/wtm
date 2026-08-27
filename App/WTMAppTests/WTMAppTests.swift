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
  #expect(model.availableStorageProviderIDs.contains(.mlx))
}

@MainActor
@Test("Known inventory values use product strings")
func inventoryValuesUseProductStrings() {
  #expect(ProviderID.huggingFace.localizedName == "Hugging Face")
  #expect(ProviderID.mlx.localizedName == "MLX")
  #expect(InstallationState.incomplete.localizedName == "Incomplete")
}

@Test("Inventory sidebar scopes do not duplicate all models")
func inventorySidebarScopesDoNotDuplicateAllModels() {
  #expect(!InventorySection.allCases.contains { $0.rawValue == "providers" })
}

@MainActor
@Test("Manual folders use source type semantics")
func manualFoldersUseSourceTypeSemantics() {
  let model = AppComposition.makeInventoryViewModel()

  #expect(ProviderID.manual.inventorySourceTypeName == "Manual Folder")
  #expect(!model.availableStorageProviderIDs.contains(.manual))
}

@Test("Installation issues are labeled as model issues")
func installationIssuesAreLabeledAsModelIssues() {
  #expect(InstallationState.issue.localizedName == "Model Issue")
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
@Test("Reset to defaults restores source and runtime settings")
func resetToDefaultsRestoresSettings() async throws {
  let defaultSource = ScanSource(
    id: "default:test",
    displayName: "Default",
    providerID: .manual,
    rootURL: FileManager.default.temporaryDirectory
  )
  let customSource = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "manual:custom",
      displayName: "Custom",
      providerID: .manual,
      rootURL: FileManager.default.temporaryDirectory,
      accessState: .allowed,
      isEnabled: true
    )
  )
  let defaultTool = ToolDefinition(
    id: UUID(),
    displayName: "Default Tool",
    role: .runtime,
    runtimeAdapterID: .llamaCpp,
    origin: .builtIn,
    isEnabled: false,
    executableURL: URL(filePath: "/usr/bin/true"),
    arguments: [.placeholder(.modelPath)],
    supportedFormats: [.gguf]
  )
  let customTool = ToolDefinition(
    id: UUID(),
    displayName: "Custom Tool",
    role: .runtime,
    runtimeAdapterID: .llamaCpp,
    origin: .imported,
    isEnabled: false,
    executableURL: URL(filePath: "/usr/bin/false"),
    arguments: [.placeholder(.modelPath)],
    supportedFormats: [.gguf]
  )
  let model = InventoryViewModel(
    coordinator: nil,
    initialSources: [defaultSource],
    sourceSettingsStore: FixtureSourceSettingsStore(
      snapshot: SourceSettingsSnapshot(
        revision: 1,
        sources: [customSource],
        hasCompletedOnboarding: true,
        scanOnLaunch: false,
        oldModelThresholdDays: 180
      )
    ),
    folderSelector: NilFolderSelector(),
    fileRevealer: NoopFileRevealer(),
    volumeCatalog: EmptyVolumeCatalog(),
    toolSettingsStore: FixtureToolSettingsStore(
      snapshot: ToolSettingsSnapshot(revision: 1, definitions: [customTool], approvals: [])
    ),
    initialToolDefinitions: [defaultTool]
  )

  await model.prepareForLaunch()
  model.resetToDefaults()

  #expect(model.sources == [defaultSource])
  #expect(!model.hasCompletedOnboarding)
  #expect(model.scanOnLaunch)
  #expect(model.oldModelThresholdDays == 90)
  #expect(model.toolDefinitions == [defaultTool])
  #expect(model.toolApprovals.isEmpty)
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

@Test("Inventory list defaults to largest models first")
func inventoryListDefaultsToLargestModelsFirst() {
  let rows = [("Small", 10), ("Large", 100)].map { name, byteCount in
    let identity = ModelIdentity(id: name, displayName: name)
    let variant = ModelVariant(id: "\(name):variant", identityID: identity.id, format: .gguf)
    let installation = ModelInstallation(
      id: name,
      identity: identity,
      variant: variant,
      sourceID: "source",
      providerID: .manual,
      rootURL: URL(filePath: "/tmp/\(name)"),
      state: .stored,
      artifacts: []
    )
    return InventoryTableRow(
      installation: installation,
      displayedByteCount: Int64(byteCount),
      reclaimableByteCount: 0
    )
  }

  #expect(rows.sorted(using: defaultInventorySortOrder).map(\.sortSize) == [100, 10])
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

private enum UpdateFixtureResponse: Sendable {
  case releases([UpdateRelease])
  case offline
  case rateLimited
  case invalidMetadata
}

private struct UpdateFixtureFetcher: UpdateReleaseFetching {
  let response: UpdateFixtureResponse

  func fetchReleases() async throws -> [UpdateRelease] {
    switch response {
    case let .releases(releases): return releases
    case .offline: throw URLError(.notConnectedToInternet)
    case .rateLimited: throw UpdateFetchError.rateLimited(retryAfter: nil)
    case .invalidMetadata: throw UpdateFetchError.invalidMetadata
    }
  }
}

private func updateVersion(_ value: String) -> SemanticVersion {
  guard let version = SemanticVersion(value) else { fatalError("Invalid fixture version") }
  return version
}

private func updateRelease(
  _ version: String,
  publishedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
  isPrerelease: Bool = false
) -> UpdateRelease {
  UpdateRelease(
    version: updateVersion(version),
    title: "WTM \(version)",
    htmlURL: UpdateChecker.releasesURL,
    publishedAt: publishedAt,
    releaseNotes: "Fixture notes",
    isPrerelease: isPrerelease
  )
}

private func updateDefaults() -> UserDefaults {
  UserDefaults(suiteName: "wtm-update-tests-\(UUID().uuidString)") ?? UserDefaults.standard
}

@Test("Update SemVer compares prereleases below the stable release")
func updateSemVerComparison() {
  #expect(updateVersion("1.0.0-rc.1") < updateVersion("1.0.0"))
  #expect(updateVersion("1.2.0") > updateVersion("1.1.9"))
  #expect(SemanticVersion("1.2") == nil)
}

@MainActor
@Test("Update checker selects the newest stable release and ignores prereleases")
func updateCheckerSelectsStableRelease() async {
  let checker = UpdateChecker(
    currentVersion: updateVersion("1.0.0"),
    fetcher: UpdateFixtureFetcher(
      response: .releases([
        updateRelease("2.0.0-rc.1", isPrerelease: true),
        updateRelease("1.1.0"),
        updateRelease("1.0.1"),
      ])
    ),
    defaults: updateDefaults()
  )

  await checker.check(now: Date(timeIntervalSince1970: 1_800_000_000))

  guard case let .updateAvailable(release) = checker.state else {
    Issue.record("Expected an available stable update")
    return
  }
  #expect(release.version == updateVersion("1.1.0"))
}

@MainActor
@Test("Update checker distinguishes current, empty, invalid, offline, and rate-limited results")
func updateCheckerDistinguishesFailureStates() async {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let cases: [(UpdateFixtureResponse, UpdateCheckState)] = [
    (.releases([updateRelease("1.0.0")]), .upToDate),
    (.releases([]), .noReleaseAvailable),
    (.invalidMetadata, .failed),
    (.offline, .offline),
    (.rateLimited, .rateLimited(retryAfter: nil)),
  ]

  for (response, expectedState) in cases {
    let checker = UpdateChecker(
      currentVersion: updateVersion("1.0.0"),
      fetcher: UpdateFixtureFetcher(response: response),
      defaults: updateDefaults()
    )
    await checker.check(now: now)
    #expect(checker.state == expectedState)
  }
}

@MainActor
@Test("Automatic update checks use a seven-day cache")
func automaticUpdateChecksUseSevenDayCache() async {
  let defaults = updateDefaults()
  let firstChecker = UpdateChecker(
    currentVersion: updateVersion("1.0.0"),
    fetcher: UpdateFixtureFetcher(response: .releases([updateRelease("1.0.1")])),
    defaults: defaults
  )
  let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
  await firstChecker.check(now: checkedAt)

  let secondChecker = UpdateChecker(
    currentVersion: updateVersion("1.0.0"),
    fetcher: UpdateFixtureFetcher(response: .invalidMetadata),
    defaults: defaults
  )
  #expect(!secondChecker.shouldAutomaticallyCheck)
  await secondChecker.checkAutomaticallyIfDue(
    now: checkedAt.addingTimeInterval(UpdateChecker.automaticCheckInterval - 1)
  )
  #expect(secondChecker.state == .idle)
  await secondChecker.checkAutomaticallyIfDue(
    now: checkedAt.addingTimeInterval(UpdateChecker.automaticCheckInterval)
  )
  #expect(secondChecker.state == .failed)
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

@Test("Menu bar summary uses the same ephemeral inventory facts")
func menuBarSummaryUsesInventoryFacts() {
  let now = Date(timeIntervalSince1970: 20_000_000)
  let summary = menuBarInventorySummary(
    installations: [
      ageFixture(timestamp: now.addingTimeInterval(-(31 * 86_400))),
      ageFixture(
        timestamp: now.addingTimeInterval(-3_600),
        state: .incomplete,
        allocatedByteCount: 4_096
      ),
    ],
    totalByteCount: 12_345,
    issueCount: 2,
    runningModelCount: 1,
    sources: [
      ScanSource(
        id: "offline",
        displayName: "Offline",
        providerID: .manual,
        rootURL: URL(filePath: "/Volumes/Offline"),
        accessState: .offline,
        isEnabled: true
      )
    ],
    oldModelThresholdDays: 30,
    now: now
  )

  #expect(summary.modelCount == 2)
  #expect(summary.totalByteCount == 12_345)
  #expect(summary.oldModelCount == 1)
  #expect(summary.incompleteByteCount == 4_096)
  #expect(summary.issueCount == 2)
  #expect(summary.runningModelCount == 1)
  #expect(summary.offlineSourceCount == 1)
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
  let source = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "manual:test",
      displayName: "Test Models",
      providerID: .manual,
      rootURL: directoryURL,
      accessState: .allowed,
      isEnabled: true
    ))
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

@Test("Legacy source settings recover a missing source identity")
func legacySourceSettingsRecoverIdentity() async throws {
  struct LegacyStoredSource: Encodable {
    let source: ScanSource
    let bookmarkData: Data?
  }

  struct LegacyPayload: Encodable {
    let version: Int
    let revision: UInt64
    let sources: [LegacyStoredSource]
    let hasCompletedOnboarding: Bool
    let scanOnLaunch: Bool
    let oldModelThresholdDays: Int?
  }

  let directoryURL = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directoryURL) }

  let source = ScanSource(
    id: "legacy-manual",
    displayName: "Legacy Models",
    providerID: .manual,
    rootURL: directoryURL,
    accessState: .stale,
    isEnabled: true
  )
  let bookmarkData = try directoryURL.bookmarkData(
    options: [],
    includingResourceValuesForKeys: [.volumeIdentifierKey, .volumeUUIDStringKey, .volumeURLKey],
    relativeTo: nil
  )
  let payload = LegacyPayload(
    version: 1,
    revision: 1,
    sources: [LegacyStoredSource(source: source, bookmarkData: bookmarkData)],
    hasCompletedOnboarding: true,
    scanOnLaunch: true,
    oldModelThresholdDays: 90
  )
  let settingsURL = directoryURL.appending(path: "source-settings.json")
  try JSONEncoder().encode(payload).write(to: settingsURL, options: [.atomic])

  let loaded = try #require(try await JSONSourceSettingsStore(settingsURL: settingsURL).load())
  let migrated = try #require(loaded.sources.first)

  #expect(migrated.rootIdentity != nil)
  #expect(migrated.accessState == .allowed)
  #expect(migrated.rootURL.standardizedFileURL == directoryURL.standardizedFileURL)

  let reloaded = try #require(
    try await JSONSourceSettingsStore(settingsURL: settingsURL).load()
  )
  #expect(reloaded.sources.first?.rootIdentity != nil)
}

@MainActor
@Test("A returning user scans enabled sources on launch")
func returningUserScansOnLaunch() async throws {
  let source = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "launch",
      displayName: "Launch",
      providerID: LaunchFixtureAdapter.providerID,
      rootURL: FileManager.default.temporaryDirectory,
      accessState: .allowed,
      isEnabled: true
    ))
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
  model.selectedSourceTypeID = .huggingFace
  #expect(model.visibleInstallations.isEmpty)
  #expect(model.inventoryEmptyState == .noMatches)
  model.selectedSourceTypeID = nil
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
  model.selectedSourceTypeID = .huggingFace
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
  let source = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "launch-disabled",
      displayName: "Launch Disabled",
      providerID: LaunchFixtureAdapter.providerID,
      rootURL: FileManager.default.temporaryDirectory,
      accessState: .allowed,
      isEnabled: true
    ))
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
  let source = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "cleanup-source",
      displayName: "Cleanup Fixture",
      providerID: .manual,
      rootURL: rootURL,
      accessState: .allowed,
      isEnabled: true
    ))
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
  let binding = try testVolumeBinding(for: modelRoot)
  let approved = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "external",
      displayName: "External Models",
      providerID: .manual,
      rootURL: modelRoot,
      volumeIdentity: binding.identity,
      accessState: .allowed,
      isEnabled: true
    ))
  let source = ScanSource(
    id: approved.id,
    displayName: approved.displayName,
    providerID: approved.providerID,
    rootURL: URL(filePath: "/Volumes/Disconnected/Models"),
    volumeIdentity: approved.volumeIdentity,
    rootIdentity: approved.rootIdentity,
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
          id: binding.identity.identifier,
          name: "External",
          rootURL: binding.volumeRootURL,
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

  let binding = try testVolumeBinding(for: modelRoot)
  let source = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "external-targeted",
      displayName: "External Models",
      providerID: LaunchFixtureAdapter.providerID,
      rootURL: modelRoot,
      volumeIdentity: binding.identity,
      accessState: .allowed,
      isEnabled: true
    ))
  let volume = MountedVolumeInfo(
    id: binding.identity.identifier,
    name: "External",
    rootURL: binding.volumeRootURL,
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

private struct TestVolumeBinding {
  let identity: VolumeIdentity
  let volumeRootURL: URL
}

private func testVolumeBinding(for rootURL: URL) throws -> TestVolumeBinding {
  let approved = try SourceApprovalPolicy().approve(
    ScanSource(
      id: "volume-binding",
      displayName: "Volume Binding",
      providerID: .manual,
      rootURL: rootURL,
      accessState: .allowed,
      isEnabled: true
    )
  )
  let rootIdentity = try #require(approved.rootIdentity)
  var volumeRootURL = rootURL.standardizedFileURL
  for _ in rootIdentity.rootRelativePath.split(separator: "/") {
    volumeRootURL.deleteLastPathComponent()
  }
  return TestVolumeBinding(
    identity: VolumeIdentity(
      identifier: rootIdentity.volumeIdentifier,
      relativePath: rootIdentity.rootRelativePath
    ),
    volumeRootURL: volumeRootURL
  )
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
    approvedFixtureSource(
      ScanSource(
        id: "manual:test",
        displayName: url.lastPathComponent,
        providerID: .manual,
        rootURL: url,
        accessState: .allowed,
        isEnabled: true
      ))
  }

  func makeMLXSource(for url: URL) -> ScanSource {
    approvedFixtureSource(
      ScanSource(
        id: "mlx:test",
        displayName: url.lastPathComponent,
        providerID: .mlx,
        rootURL: url,
        accessState: .allowed,
        isEnabled: true
      ))
  }

  func replace(_ source: ScanSource, with url: URL) -> ScanSource {
    approvedFixtureSource(
      ScanSource(
        id: source.id,
        displayName: source.displayName,
        providerID: source.providerID,
        rootURL: url,
        accessState: .allowed,
        isEnabled: true
      ))
  }
}

private func approvedFixtureSource(_ source: ScanSource) -> ScanSource {
  guard let approved = try? SourceApprovalPolicy().approve(source) else {
    preconditionFailure("Fixture source must be approvable")
  }
  return approved
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

private func ageFixture(
  timestamp: Date?,
  state: InstallationState = .stored,
  allocatedByteCount: Int64 = 0
) -> ModelInstallation {
  let identity = ModelIdentity(id: "age", displayName: "Age Model")
  let variant = ModelVariant(id: "age:variant", identityID: identity.id, format: .gguf)
  return ModelInstallation(
    id: "age:model",
    identity: identity,
    variant: variant,
    sourceID: "source",
    providerID: .manual,
    rootURL: URL(filePath: "/tmp/age-model"),
    state: state,
    artifacts: allocatedByteCount > 0
      ? [
        Artifact(
          id: "age:artifact:\(state.rawValue)",
          url: URL(filePath: "/tmp/age-model/weights.gguf"),
          kind: .weights,
          logicalByteCount: allocatedByteCount,
          allocatedByteCount: allocatedByteCount,
          physicalIdentifier: "age:physical:\(state.rawValue)"
        )
      ] : [],
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
