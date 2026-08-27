import Foundation
import Testing
import WTMAdapterContracts
import WTMSecurity

@testable import WTMDomain
@testable import WTMInventory

private var testHomeURL: URL {
  URL(
    filePath: ProcessInfo.processInfo.environment["WTM_TEST_HOME_PATH"] ?? "/tmp/wtm-test-home",
    directoryHint: .isDirectory
  )
}

@Test("Disabled sources are never passed to an adapter")
func disabledSourceIsRejected() async throws {
  let registry = try AdapterRegistry(adapters: [FixtureAdapter()])
  let coordinator = InventoryCoordinator(registry: registry)
  let source = ScanSource(
    id: "disabled",
    displayName: "Disabled",
    providerID: FixtureAdapter.providerID,
    rootURL: URL(filePath: "/tmp"),
    accessState: .allowed,
    isEnabled: false
  )

  let result = await coordinator.scan(source: source)

  #expect(result.installations.isEmpty)
  #expect(result.issues.map(\.code) == ["SOURCE_NOT_ALLOWED"])
}

@Test("Source access failures remain explicit and do not reach adapters")
func sourceAccessFailuresAreExplicit() async throws {
  let registry = try AdapterRegistry(adapters: [FixtureAdapter()])
  let coordinator = InventoryCoordinator(registry: registry)
  let expectations: [(SourceAccessState, String)] = [
    (.offline, "SOURCE_OFFLINE"),
    (.denied, "SOURCE_NOT_READABLE"),
    (.stale, "SOURCE_ACCESS_STALE"),
  ]

  for (accessState, expectedCode) in expectations {
    let source = ScanSource(
      id: accessState.rawValue,
      displayName: accessState.rawValue,
      providerID: FixtureAdapter.providerID,
      rootURL: URL(filePath: "/tmp"),
      accessState: accessState,
      isEnabled: true
    )
    let result = await coordinator.scan(source: source)
    #expect(result.installations.isEmpty)
    #expect(result.issues.map(\.code) == [expectedCode])
  }
}

@Test("Physical artifacts are counted only once")
func sharedAllocatedBytesAreDeduplicated() {
  let artifactA = fixtureArtifact(id: "a", physicalIdentifier: "inode-1")
  let artifactB = fixtureArtifact(id: "b", physicalIdentifier: "inode-1")
  let snapshot = InventorySnapshot(
    installations: [
      fixtureInstallation(id: "one", artifact: artifactA),
      fixtureInstallation(id: "two", artifact: artifactB),
    ],
    issues: [],
    scannedSourceIDs: ["source"]
  )

  #expect(snapshot.uniqueAllocatedByteCount == 4_096)
}

@Test("Storage breakdown separates exclusive, shared, and unknown bytes")
func storageBreakdownUsesOneHundredPercentScope() {
  let exclusive = fixtureArtifact(id: "exclusive", physicalIdentifier: "inode-exclusive")
  let sharedA = fixtureArtifact(id: "shared-a", physicalIdentifier: "inode-shared")
  let sharedB = fixtureArtifact(id: "shared-b", physicalIdentifier: "inode-shared")
  let unknown = Artifact(
    id: "unknown",
    url: URL(filePath: "/tmp/unknown"),
    kind: .weights,
    logicalByteCount: 2_048,
    allocatedByteCount: 2_048
  )
  let first = fixtureInstallation(id: "first", artifacts: [exclusive, sharedA])
  let second = fixtureInstallation(id: "second", artifacts: [sharedB, unknown])

  let breakdown = InventoryStorageBreakdown(installations: [first, second])

  #expect(breakdown.exclusiveByteCount(for: first.id) == 4_096)
  #expect(breakdown.exclusiveByteCount(for: second.id) == 0)
  #expect(breakdown.sharedByteCount == 4_096)
  #expect(breakdown.unknownByteCount == 2_048)
  #expect(breakdown.totalByteCount == 10_240)
}

@Test("Provider installations suppress overlapping manual cache views")
func providerInstallationsSuppressManualDuplicates() {
  let weightsURL = URL(filePath: "/cache/models--acme--model/snapshots/local/model.safetensors")
  let provider = duplicateFixtureInstallation(
    id: "hf:model",
    providerID: .huggingFace,
    rootURL: weightsURL.deletingLastPathComponent(),
    artifactURLs: [weightsURL]
  )
  let manual = duplicateFixtureInstallation(
    id: "manual:local",
    providerID: .manual,
    rootURL: weightsURL.deletingLastPathComponent(),
    artifactURLs: [weightsURL]
  )

  let reconciled = InstallationReconciler().reconcile([manual, provider])

  #expect(reconciled.map(\.id) == [provider.id])
}

@Test("Same physical model at a distinct path remains a separate installation")
func distinctInstallationPathsArePreserved() {
  let providerURL = URL(filePath: "/cache/provider/model.gguf")
  let manualURL = URL(filePath: "/Models/model.gguf")
  let provider = duplicateFixtureInstallation(
    id: "hf:model",
    providerID: .huggingFace,
    rootURL: providerURL,
    artifactURLs: [providerURL],
    physicalIdentifier: "inode-1"
  )
  let manual = duplicateFixtureInstallation(
    id: "manual:model",
    providerID: .manual,
    rootURL: manualURL,
    artifactURLs: [manualURL],
    physicalIdentifier: "inode-1"
  )

  let reconciled = InstallationReconciler().reconcile([provider, manual])

  #expect(Set(reconciled.map(\.id)) == [provider.id, manual.id])
}

@Test("Provider sources scan before overlapping manual sources")
func providerSourcesHaveDeterministicPriority() async throws {
  let registry = try AdapterRegistry(adapters: [
    OrderedFixtureAdapter(id: .huggingFace),
    OrderedFixtureAdapter(id: .manual),
  ])
  let coordinator = InventoryCoordinator(registry: registry)
  let sources = [
    allowedSource(id: "manual", providerID: .manual),
    allowedSource(id: "hugging-face", providerID: .huggingFace),
  ]
  var startedSourceIDs: [String] = []

  for await event in coordinator.scanEvents(sources: sources) {
    if case .sourceStarted(let source, _, _) = event {
      startedSourceIDs.append(source.id)
    }
  }

  #expect(startedSourceIDs == ["hugging-face", "manual"])
}

@Test("Source prioritizer prefers nested roots and retains their parent")
func sourcePrioritizerPrefersNestedRoots() {
  let rootURL = URL(filePath: "/tmp/wtm-home")
  let nestedURL = rootURL.appending(path: ".models", directoryHint: .isDirectory)
  let sources = [
    ScanSource(
      id: "nested",
      displayName: "Nested",
      providerID: .manual,
      rootURL: nestedURL,
      accessState: .allowed,
      isEnabled: true
    ),
    ScanSource(
      id: "nested-duplicate",
      displayName: "Nested Duplicate",
      providerID: .manual,
      rootURL: nestedURL,
      accessState: .allowed,
      isEnabled: true
    ),
    ScanSource(
      id: "root",
      displayName: "Root",
      providerID: .manual,
      rootURL: rootURL,
      accessState: .allowed,
      isEnabled: true
    ),
  ]

  #expect(SourcePrioritizer().prioritize(sources).map(\.id) == ["nested", "root"])
}

@Test("Provider-specific sources remain separate when paths overlap")
func overlappingProviderSourcesRemainSeparate() {
  let rootURL = URL(filePath: "/tmp/wtm-home")
  let sources = [
    ScanSource(
      id: "manual",
      displayName: "Manual",
      providerID: .manual,
      rootURL: rootURL,
      accessState: .allowed,
      isEnabled: true
    ),
    ScanSource(
      id: "mlx",
      displayName: "MLX",
      providerID: .mlx,
      rootURL: rootURL,
      accessState: .allowed,
      isEnabled: true
    ),
  ]

  #expect(ScanSourcePathFilter().filter(sources).map(\.id) == ["manual", "mlx"])
}

@Test("Coordinator scans nested same-provider sources before their parent")
func coordinatorPrioritizesNestedSources() async throws {
  let rootURL = FileManager.default.temporaryDirectory.appending(
    path: "wtm-scan-filter-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
  let nestedURL = rootURL.appending(path: ".models", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: rootURL) }

  let sources = [
    allowedSource(id: "nested", providerID: FixtureAdapter.providerID, rootURL: nestedURL),
    allowedSource(id: "root", providerID: FixtureAdapter.providerID, rootURL: rootURL),
  ]
  let coordinator = InventoryCoordinator(
    registry: try AdapterRegistry(adapters: [FixtureAdapter()])
  )
  var startedSourceIDs: [String] = []

  for await event in coordinator.scanEvents(sources: sources) {
    if case .sourceStarted(let source, _, _) = event {
      startedSourceIDs.append(source.id)
    }
  }

  #expect(startedSourceIDs == ["nested", "root"])
}

@Test("Scan events preserve source order and bound installation batches")
func scanEventsAreOrderedAndBounded() async throws {
  let registry = try AdapterRegistry(adapters: [FixtureAdapter(installationCount: 3)])
  let coordinator = InventoryCoordinator(registry: registry, installationBatchSize: 2)
  let rootURL = FileManager.default.temporaryDirectory.appending(
    path: "wtm-scan-order-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: rootURL) }
  let firstRoot = rootURL.appending(path: "first", directoryHint: .isDirectory)
  let secondRoot = rootURL.appending(path: "second", directoryHint: .isDirectory)
  for root in [firstRoot, secondRoot] {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }
  let sources = [
    allowedSource(id: "first", providerID: FixtureAdapter.providerID, rootURL: firstRoot),
    allowedSource(id: "second", providerID: FixtureAdapter.providerID, rootURL: secondRoot),
  ]

  var startedSourceIDs: [String] = []
  var batchSizes: [Int] = []
  var finishedSourceIDs: Set<String> = []
  for await event in coordinator.scanEvents(sources: sources) {
    switch event {
    case .sourceStarted(let source, _, _):
      startedSourceIDs.append(source.id)
    case .batch(_, let installations, _):
      batchSizes.append(installations.count)
    case .finished(let sourceIDs, _):
      finishedSourceIDs = sourceIDs
    default:
      break
    }
  }

  #expect(startedSourceIDs == ["first", "second"])
  #expect(batchSizes == [2, 1, 2, 1])
  #expect(finishedSourceIDs == ["first", "second"])
}

@Test("Coordinator forwards adapter batches before the source finishes")
func adapterBatchesRemainIncremental() async throws {
  let registry = try AdapterRegistry(adapters: [StreamingFixtureAdapter()])
  let coordinator = InventoryCoordinator(registry: registry)
  let source = allowedSource(id: "stream", providerID: StreamingFixtureAdapter.providerID)
  var eventOrder: [String] = []

  for await event in coordinator.scanEvents(sources: [source]) {
    switch event {
    case .batch(_, let installations, _):
      eventOrder.append(contentsOf: installations.map(\.id))
    case .sourceFinished:
      eventOrder.append("finished")
    default:
      break
    }
  }

  #expect(eventOrder == ["stream-first", "stream-second", "finished"])
}

private struct FixtureAdapter: StorageProviderAdapter {
  static let providerID = ProviderID(rawValue: "fixture")
  let id = providerID
  let displayName = "Fixture"
  let installationCount: Int

  init(installationCount: Int = 0) {
    self.installationCount = installationCount
  }

  func scan(source: ScanSource) async -> AdapterScanResult {
    AdapterScanResult(
      source: source,
      installations: (0..<installationCount).map { index in
        fixtureInstallation(
          id: "\(source.id)-\(index)",
          artifact: fixtureArtifact(
            id: "\(source.id)-\(index)",
            physicalIdentifier: "inode-\(source.id)-\(index)"
          )
        )
      }
    )
  }
}

private struct OrderedFixtureAdapter: StorageProviderAdapter {
  let id: ProviderID
  let displayName = "Ordered Fixture"

  func scan(source: ScanSource) async -> AdapterScanResult {
    AdapterScanResult(source: source, installations: [])
  }
}

private struct StreamingFixtureAdapter: StorageProviderAdapter {
  static let providerID = ProviderID(rawValue: "streaming-fixture")
  let id = providerID
  let displayName = "Streaming Fixture"

  func scan(source: ScanSource) async -> AdapterScanResult {
    AdapterScanResult(source: source, installations: [])
  }

  func scanBatches(source _: ScanSource) -> AsyncStream<AdapterScanBatch> {
    AsyncStream { continuation in
      continuation.yield(
        AdapterScanBatch(
          installations: [
            fixtureInstallation(
              id: "stream-first",
              artifact: fixtureArtifact(id: "stream-first", physicalIdentifier: "stream-first")
            )
          ]
        )
      )
      continuation.yield(
        AdapterScanBatch(
          installations: [
            fixtureInstallation(
              id: "stream-second",
              artifact: fixtureArtifact(
                id: "stream-second",
                physicalIdentifier: "stream-second"
              )
            )
          ]
        )
      )
      continuation.finish()
    }
  }
}

@Test("Default sources are narrow, deterministic, and disabled")
func defaultSourcesAreSafeAndDeterministic() {
  let home = testHomeURL
  let sources = DefaultSourceCatalog().suggestions(homeDirectory: home)

  #expect(DefaultSourceCatalog.version == 2)
  #expect(
    sources.map(\.id)
      == ["default:ollama", "default:hugging-face", "default:unsloth", "default:models"]
  )
  #expect(sources[2].rootURL.path == home.appending(path: ".unsloth").path)
  #expect(sources.allSatisfy { !$0.isEnabled })
  #expect(!sources.map(\.rootURL.path).contains(home.path))
  #expect(!sources.map(\.rootURL.path).contains(home.appending(path: ".cache").path))
}

@Test("Configuration policy allows harmless metadata and rejects secret files")
func configurationPolicyRejectsSecrets() {
  let policy = ConfigurationFilePolicy()

  #expect(policy.isAllowed(URL(filePath: "/model/config.json")))
  #expect(policy.isAllowed(URL(filePath: "/model/.metadata.json")))
  #expect(!policy.isAllowed(URL(filePath: "/model/.env")))
  #expect(!policy.isAllowed(URL(filePath: "/model/api_key.json")))
  #expect(policy.isSecretSuspect(URL(filePath: "/model/id_ed25519.key")))
}

private func fixtureArtifact(id: String, physicalIdentifier: String) -> Artifact {
  Artifact(
    id: id,
    url: URL(filePath: "/tmp/\(id)"),
    kind: .weights,
    logicalByteCount: 4_096,
    allocatedByteCount: 4_096,
    physicalIdentifier: physicalIdentifier,
    isShared: true
  )
}

private func fixtureInstallation(id: String, artifact: Artifact) -> ModelInstallation {
  fixtureInstallation(id: id, artifacts: [artifact])
}

private func fixtureInstallation(id: String, artifacts: [Artifact]) -> ModelInstallation {
  let identity = ModelIdentity(id: "identity", displayName: "Fixture")
  let variant = ModelVariant(id: "variant", identityID: identity.id, format: .gguf)
  return ModelInstallation(
    id: id,
    identity: identity,
    variant: variant,
    sourceID: "source",
    providerID: .manual,
    rootURL: artifacts.first?.url ?? URL(filePath: "/tmp"),
    state: .stored,
    artifacts: artifacts
  )
}

private func duplicateFixtureInstallation(
  id: String,
  providerID: ProviderID,
  rootURL: URL,
  artifactURLs: [URL],
  physicalIdentifier: String = "inode-cache"
) -> ModelInstallation {
  let identity = ModelIdentity(id: id, displayName: id)
  let variant = ModelVariant(id: "\(id):variant", identityID: identity.id, format: .safetensors)
  return ModelInstallation(
    id: id,
    identity: identity,
    variant: variant,
    sourceID: "source",
    providerID: providerID,
    rootURL: rootURL,
    state: .stored,
    artifacts: artifactURLs.map { url in
      Artifact(
        id: "\(id):\(url.lastPathComponent)",
        url: url,
        kind: .weights,
        logicalByteCount: 4_096,
        allocatedByteCount: 4_096,
        physicalIdentifier: physicalIdentifier
      )
    }
  )
}

private func allowedSource(
  id: String,
  providerID: ProviderID,
  rootURL: URL = FileManager.default.temporaryDirectory
) -> ScanSource {
  guard let identity = try? SourceRootPolicy().capture(rootURL: rootURL) else {
    preconditionFailure("Fixture source must be approvable")
  }
  return ScanSource(
    id: id,
    displayName: id,
    providerID: providerID,
    rootURL: rootURL,
    rootIdentity: identity,
    accessState: .allowed,
    isEnabled: true
  )
}
