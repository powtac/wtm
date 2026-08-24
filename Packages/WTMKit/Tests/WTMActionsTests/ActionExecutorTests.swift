import Foundation
import Synchronization
import Testing
import WTMActions
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

@Test("A replaced file invalidates its deletion preview")
func replacedFileInvalidatesPreview() async throws {
  let fixture = try ActionFixture()
  defer { fixture.cleanup() }
  let adapter = FixtureActionAdapter(providerID: .manual)
  let trashMover = RecordingTrashMover()
  let executor = try makeExecutor(adapter: adapter, trashMover: trashMover)
  let plan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )

  try FileManager.default.removeItem(at: fixture.fileURL)
  try Data("replacement".utf8).write(to: fixture.fileURL)

  await #expect(throws: ActionExecutorError.targetRevalidationFailed) {
    try await executor.execute(
      plan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }
  #expect(await trashMover.movedURLs().isEmpty)
}

@Test("A symlink swap invalidates its deletion preview")
func symlinkSwapInvalidatesPreview() async throws {
  let directoryURL = temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directoryURL) }
  try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  let firstURL = directoryURL.appending(path: "first.gguf")
  let secondURL = directoryURL.appending(path: "second.gguf")
  let linkURL = directoryURL.appending(path: "model.gguf")
  try Data("first".utf8).write(to: firstURL)
  try Data("second".utf8).write(to: secondURL)
  try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: firstURL)
  let fixture = try ActionFixture(rootURL: directoryURL, fileURL: linkURL)
  let trashMover = RecordingTrashMover()
  let executor = try makeExecutor(
    adapter: FixtureActionAdapter(providerID: .manual),
    trashMover: trashMover
  )
  let plan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )

  try FileManager.default.removeItem(at: linkURL)
  try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: secondURL)

  await #expect(throws: ActionExecutorError.targetRevalidationFailed) {
    try await executor.execute(
      plan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }
}

@Test("Expired plans and stale generations are rejected")
func expiredAndStalePlansAreRejected() async throws {
  let fixture = try ActionFixture()
  defer { fixture.cleanup() }
  let clock = Mutex(Date(timeIntervalSince1970: 1_000))
  let registry = try StorageActionAdapterRegistry(adapters: [
    FixtureActionAdapter(providerID: .manual)
  ])
  let executor = ActionExecutor(
    registry: registry,
    trashMover: RecordingTrashMover(),
    auditStore: InMemoryActionAuditStore(),
    planLifetime: 5,
    now: { clock.withLock { $0 } }
  )
  let expiredPlan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )
  clock.withLock { $0 = $0.addingTimeInterval(6) }

  await #expect(throws: ActionExecutorError.planExpired) {
    try await executor.execute(
      expiredPlan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }

  clock.withLock { $0 = Date(timeIntervalSince1970: 2_000) }
  let firstPlan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )
  _ = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )
  await #expect(throws: ActionExecutorError.planNotActive) {
    try await executor.execute(
      firstPlan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }
}

@Test("Irreversible operations require a separate confirmation")
func irreversibleOperationsRequireConfirmation() async throws {
  let fixture = try ActionFixture(providerID: .ollama)
  defer { fixture.cleanup() }
  let adapter = IrreversibleFixtureActionAdapter()
  let registry = try StorageActionAdapterRegistry(adapters: [adapter])
  let audit = InMemoryActionAuditStore()
  let executor = ActionExecutor(
    registry: registry,
    trashMover: RecordingTrashMover(),
    auditStore: audit
  )
  let plan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )

  await #expect(throws: ActionExecutorError.irreversibleConfirmationRequired) {
    try await executor.execute(
      plan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }
  let entries = await audit.entries()
  #expect(entries.count == 1)
  #expect(entries[0].status == .blocked)
  #expect(entries[0].includedIrreversibleOperation)
}

@Test("A failed mutation stops later operations and reports a partial result")
func partialFailureStopsLaterOperations() async throws {
  let directoryURL = temporaryDirectory()
  defer { try? FileManager.default.removeItem(at: directoryURL) }
  try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  let firstURL = directoryURL.appending(path: "a.gguf")
  let secondURL = directoryURL.appending(path: "b.gguf")
  try Data("a".utf8).write(to: firstURL)
  try Data("b".utf8).write(to: secondURL)
  let fixture = try ActionFixture(rootURL: directoryURL, fileURL: firstURL)
  let secondInstallation = try fixture.installation(replacingFileURL: secondURL, id: "second")
  let trashMover = RecordingTrashMover(failingAtCall: 2)
  let executor = try makeExecutor(
    adapter: FixtureActionAdapter(providerID: .manual),
    trashMover: trashMover
  )
  let inventory = [fixture.installation, secondInstallation]
  let plan = try await executor.prepareDeletion(
    installationIDs: Set(inventory.map(\.id)),
    currentInventory: inventory,
    sources: [fixture.source]
  )

  let report = try await executor.execute(
    plan,
    currentInventory: inventory,
    sources: [fixture.source],
    confirmedIrreversible: false
  )

  #expect(report.status == .partial)
  #expect(report.operationResults.count { $0.status == .succeeded } == 1)
  #expect(report.operationResults.count { $0.status == .failed } == 1)
}

@Test("A Trash operation remains recoverable in an isolated fixture")
func trashOperationCanBeRecovered() async throws {
  let fixture = try ActionFixture()
  defer { fixture.cleanup() }
  let trashMover = RecoverableTrashMover(
    trashDirectoryURL: fixture.rootURL.appending(path: ".Trash", directoryHint: .isDirectory)
  )
  let executor = try makeExecutor(
    adapter: FixtureActionAdapter(providerID: .manual),
    trashMover: trashMover
  )
  let plan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )

  let report = try await executor.execute(
    plan,
    currentInventory: [fixture.installation],
    sources: [fixture.source],
    confirmedIrreversible: false
  )

  #expect(report.status == .succeeded)
  #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
  try await trashMover.restoreAll()
  #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
  #expect(try Data(contentsOf: fixture.fileURL) == Data("model".utf8))
}

@Test("Overlapping batch targets form a blocking conflict graph")
func overlappingTargetsBlockBatch() async throws {
  let rootURL = temporaryDirectory()
  let modelDirectoryURL = rootURL.appending(path: "model", directoryHint: .isDirectory)
  let fileURL = modelDirectoryURL.appending(path: "model.gguf")
  try FileManager.default.createDirectory(
    at: modelDirectoryURL,
    withIntermediateDirectories: true
  )
  try Data("model".utf8).write(to: fileURL)
  let fixture = try ActionFixture(rootURL: rootURL, fileURL: fileURL)
  defer { fixture.cleanup() }
  let adapter = OverlappingFixtureActionAdapter()
  let registry = try StorageActionAdapterRegistry(adapters: [adapter])
  let executor = ActionExecutor(
    registry: registry,
    trashMover: RecordingTrashMover(),
    auditStore: InMemoryActionAuditStore()
  )
  let plan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )

  #expect(plan.conflicts.count == 1)
  await #expect(throws: ActionExecutorError.planConflict) {
    try await executor.execute(
      plan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }
}

@Test("An open deletion target creates a blocking preview conflict")
func openTargetCreatesBlockingConflict() async throws {
  let fixture = try ActionFixture()
  defer { fixture.cleanup() }
  let trashMover = RecordingTrashMover()
  let executor = ActionExecutor(
    registry: try StorageActionAdapterRegistry(adapters: [
      FixtureActionAdapter(providerID: .manual)
    ]),
    trashMover: trashMover,
    auditStore: InMemoryActionAuditStore(),
    openFileUsageChecker: FixedOpenFileUsageChecker(paths: [fixture.fileURL.path])
  )

  let plan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )

  #expect(plan.conflicts.map(\.reason) == [.modelInUse])
  await #expect(throws: ActionExecutorError.planConflict) {
    try await executor.execute(
      plan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }
  #expect(await trashMover.movedURLs().isEmpty)
}

@Test("A target opened after preview is blocked during revalidation")
func newlyOpenedTargetIsBlockedDuringRevalidation() async throws {
  let fixture = try ActionFixture()
  defer { fixture.cleanup() }
  let checker = SequencedOpenFileUsageChecker(results: [[], [fixture.fileURL.path]])
  let trashMover = RecordingTrashMover()
  let executor = ActionExecutor(
    registry: try StorageActionAdapterRegistry(adapters: [
      FixtureActionAdapter(providerID: .manual)
    ]),
    trashMover: trashMover,
    auditStore: InMemoryActionAuditStore(),
    openFileUsageChecker: checker
  )
  let plan = try await executor.prepareDeletion(
    installationIDs: [fixture.installation.id],
    currentInventory: [fixture.installation],
    sources: [fixture.source]
  )

  await #expect(throws: ActionExecutorError.targetInUse) {
    try await executor.execute(
      plan,
      currentInventory: [fixture.installation],
      sources: [fixture.source],
      confirmedIrreversible: false
    )
  }
  #expect(await trashMover.movedURLs().isEmpty)
}

@Test("The macOS usage checker identifies an open fixture file")
func systemUsageCheckerIdentifiesOpenFile() async throws {
  let fixture = try ActionFixture()
  defer { fixture.cleanup() }
  let handle = try FileHandle(forReadingFrom: fixture.fileURL)
  defer { try? handle.close() }
  let target = DeletionFileTarget(
    url: fixture.fileURL,
    sourceID: fixture.source.id,
    sourceRootURL: fixture.source.rootURL,
    identity: try DeletionTargetPolicy().captureIdentity(
      for: fixture.fileURL,
      under: fixture.source.rootURL
    ),
    allocatedByteCount: 1,
    displayName: fixture.fileURL.lastPathComponent
  )

  let openPaths = await SystemOpenFileUsageChecker().openTargetPaths(in: [target])

  #expect(openPaths == [fixture.fileURL.path])
}

@Test("Path containment rejects traversal candidates")
func pathContainmentRejectsTraversalCandidates() throws {
  let rootURL = URL(filePath: "/tmp/wtm-action-root", directoryHint: .isDirectory)
  let policy = DeletionTargetPolicy()
  for index in 0..<200 {
    let outsideURL =
      rootURL
      .appending(path: "child")
      .appending(path: "..")
      .appending(path: "..")
      .appending(path: "outside-\(index)")
    #expect(throws: DeletionTargetPolicyError.targetOutsideSource) {
      try policy.validateContainment(of: outsideURL, under: rootURL)
    }
  }
  #expect(throws: DeletionTargetPolicyError.sourceRootTargeted) {
    try policy.validateContainment(of: rootURL, under: rootURL)
  }
}

@Test("Deletion target policy rejects read-only volumes")
func deletionTargetPolicyRejectsReadOnlyVolumes() {
  let policy = DeletionTargetPolicy(volumeIsReadOnly: { _ in true })

  #expect(throws: DeletionTargetPolicyError.sourceVolumeReadOnly) {
    try policy.validateWritableVolume(containing: URL(filePath: "/fixture"))
  }
}

private func makeExecutor(
  adapter: any StorageActionAdapter,
  trashMover: any TrashMoving
) throws -> ActionExecutor {
  ActionExecutor(
    registry: try StorageActionAdapterRegistry(adapters: [adapter]),
    trashMover: trashMover,
    auditStore: InMemoryActionAuditStore(),
    openFileUsageChecker: FixedOpenFileUsageChecker(paths: [])
  )
}

private struct FixtureActionAdapter: StorageActionAdapter {
  let id: ProviderID
  let displayName = "Fixture"

  init(providerID: ProviderID) { id = providerID }

  func makeDeletionPlan(context: DeletionPlanningContext) throws -> ProviderDeletionPlan {
    let policy = DeletionTargetPolicy()
    let operations = try context.selectedInstallations.map { installation in
      guard let artifact = installation.artifacts.first,
        let source = context.source(for: installation.sourceID)
      else { throw StorageActionAdapterError.invalidSelection }
      let identity = try policy.captureIdentity(for: artifact.url, under: source.rootURL)
      return DeletionOperation(
        id: "fixture:\(artifact.url.path)",
        providerID: id,
        installationIDs: [installation.id],
        reversibility: .trash,
        expectedReclaimableByteCount: artifact.allocatedByteCount,
        payload: .trash(
          DeletionFileTarget(
            url: artifact.url,
            sourceID: source.id,
            sourceRootURL: source.rootURL,
            identity: identity,
            allocatedByteCount: artifact.allocatedByteCount,
            displayName: artifact.url.lastPathComponent
          )
        )
      )
    }
    return ProviderDeletionPlan(
      providerID: id,
      models: context.selectedInstallations.map(summary),
      operations: operations
    )
  }
}

private struct IrreversibleFixtureActionAdapter: StorageActionAdapter {
  let id = ProviderID.ollama
  let displayName = "Ollama Fixture"

  func makeDeletionPlan(context: DeletionPlanningContext) -> ProviderDeletionPlan {
    ProviderDeletionPlan(
      providerID: id,
      models: context.selectedInstallations.map(summary),
      operations: [
        DeletionOperation(
          id: "ollama:delete:model",
          providerID: id,
          installationIDs: context.selectedInstallations.map(\.id),
          reversibility: .irreversible,
          expectedReclaimableByteCount: 1,
          payload: .provider(
            ProviderDeletionRequest(kind: .ollamaModel, identifier: "model:latest")
          )
        )
      ]
    )
  }

  func execute(_ request: ProviderDeletionRequest) async throws {}
}

private struct OverlappingFixtureActionAdapter: StorageActionAdapter {
  let id = ProviderID.manual
  let displayName = "Overlap Fixture"

  func makeDeletionPlan(context: DeletionPlanningContext) throws -> ProviderDeletionPlan {
    guard let installation = context.selectedInstallations.first,
      let source = context.source(for: installation.sourceID)
    else { throw StorageActionAdapterError.invalidSelection }
    let policy = DeletionTargetPolicy()
    let parentURL = installation.rootURL
    let childURL = installation.artifacts[0].url
    let urls = [parentURL, childURL]
    let operations = try urls.map { url in
      let identity = try policy.captureIdentity(for: url, under: source.rootURL)
      return DeletionOperation(
        id: "overlap:\(url.path)",
        providerID: id,
        installationIDs: [installation.id],
        reversibility: .trash,
        expectedReclaimableByteCount: 1,
        payload: .trash(
          DeletionFileTarget(
            url: url,
            sourceID: source.id,
            sourceRootURL: source.rootURL,
            identity: identity,
            allocatedByteCount: 1,
            displayName: url.lastPathComponent
          )
        )
      )
    }
    return ProviderDeletionPlan(
      providerID: id,
      models: context.selectedInstallations.map(summary),
      operations: operations
    )
  }
}

private actor RecordingTrashMover: TrashMoving {
  private let failingAtCall: Int?
  private var calls: [URL] = []

  init(failingAtCall: Int? = nil) {
    self.failingAtCall = failingAtCall
  }

  func moveToTrash(_ url: URL) throws {
    calls.append(url)
    if calls.count == failingAtCall { throw FixtureError.expectedFailure }
  }

  func movedURLs() -> [URL] { calls }
}

private actor RecoverableTrashMover: TrashMoving {
  private let trashDirectoryURL: URL
  private var moves: [(original: URL, trashed: URL)] = []

  init(trashDirectoryURL: URL) {
    self.trashDirectoryURL = trashDirectoryURL
  }

  func moveToTrash(_ url: URL) throws {
    try FileManager.default.createDirectory(
      at: trashDirectoryURL,
      withIntermediateDirectories: true
    )
    let trashedURL = trashDirectoryURL.appending(path: UUID().uuidString)
    try FileManager.default.moveItem(at: url, to: trashedURL)
    moves.append((url, trashedURL))
  }

  func restoreAll() throws {
    for move in moves.reversed() {
      try FileManager.default.moveItem(at: move.trashed, to: move.original)
    }
    moves = []
  }
}

private struct FixedOpenFileUsageChecker: OpenFileUsageChecking {
  let paths: Set<String>

  func openTargetPaths(in _: [DeletionFileTarget]) -> Set<String> { paths }
}

private actor SequencedOpenFileUsageChecker: OpenFileUsageChecking {
  private var results: [Set<String>]

  init(results: [Set<String>]) {
    self.results = results
  }

  func openTargetPaths(in _: [DeletionFileTarget]) -> Set<String> {
    guard !results.isEmpty else { return [] }
    return results.removeFirst()
  }
}

private struct ActionFixture {
  let rootURL: URL
  let fileURL: URL
  let source: ScanSource
  let installation: ModelInstallation

  init(providerID: ProviderID = .manual) throws {
    let rootURL = temporaryDirectory()
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let fileURL = rootURL.appending(path: "model.gguf")
    try Data("model".utf8).write(to: fileURL)
    try self.init(rootURL: rootURL, fileURL: fileURL, providerID: providerID)
  }

  init(
    rootURL: URL,
    fileURL: URL,
    providerID: ProviderID = .manual
  ) throws {
    self.rootURL = rootURL
    self.fileURL = fileURL
    source = ScanSource(
      id: "fixture-source",
      displayName: "Fixture",
      providerID: providerID,
      rootURL: rootURL,
      accessState: .allowed,
      isEnabled: true
    )
    installation = try Self.installation(
      fileURL: fileURL,
      source: source,
      providerID: providerID,
      id: "fixture-installation"
    )
  }

  func installation(replacingFileURL fileURL: URL, id: String) throws -> ModelInstallation {
    try Self.installation(fileURL: fileURL, source: source, providerID: source.providerID, id: id)
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: rootURL)
  }

  private static func installation(
    fileURL: URL,
    source: ScanSource,
    providerID: ProviderID,
    id: String
  ) throws -> ModelInstallation {
    let metadata = try FileMetadataReader().metadata(for: fileURL)
    let identity = ModelIdentity(id: id, displayName: id)
    return ModelInstallation(
      id: id,
      identity: identity,
      variant: ModelVariant(id: "\(id):variant", identityID: id, format: .gguf),
      sourceID: source.id,
      providerID: providerID,
      rootURL: fileURL.deletingLastPathComponent(),
      state: .stored,
      artifacts: [
        Artifact(
          id: "artifact:\(id)",
          url: fileURL,
          kind: .weights,
          logicalByteCount: metadata.logicalByteCount,
          allocatedByteCount: metadata.allocatedByteCount,
          physicalIdentifier: metadata.physicalIdentifier
        )
      ]
    )
  }
}

private func summary(_ installation: ModelInstallation) -> DeletionModelSummary {
  DeletionModelSummary(
    id: installation.id,
    displayName: installation.identity.displayName,
    providerID: installation.providerID,
    sourceID: installation.sourceID,
    artifactCount: installation.artifacts.count,
    allocatedByteCount: installation.allocatedByteCount
  )
}

private func temporaryDirectory() -> URL {
  FileManager.default.temporaryDirectory.appending(
    path: "wtm-actions-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
}

private enum FixtureError: Error {
  case expectedFailure
}
