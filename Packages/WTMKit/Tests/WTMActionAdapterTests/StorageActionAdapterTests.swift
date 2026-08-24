import ActionHuggingFace
import ActionManual
import ActionOllama
import Foundation
import Testing
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

@Test("Manual cleanup excludes secrets and remaining physical references")
func manualCleanupExcludesProtectedAndSharedFiles() async throws {
  let rootURL = temporaryActionDirectory()
  defer { try? FileManager.default.removeItem(at: rootURL) }
  try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  let modelURL = rootURL.appending(path: "model.gguf")
  let secretURL = rootURL.appending(path: "id_ed25519")
  let sharedURL = rootURL.appending(path: "shared.safetensors")
  try Data("model".utf8).write(to: modelURL)
  try Data("secret".utf8).write(to: secretURL)
  try Data("shared".utf8).write(to: sharedURL)
  let source = actionSource(id: "manual", providerID: .manual, rootURL: rootURL)
  let selected = try actionInstallation(
    id: "selected",
    providerID: .manual,
    source: source,
    files: [modelURL, secretURL, sharedURL]
  )
  let remaining = try actionInstallation(
    id: "remaining",
    providerID: .manual,
    source: source,
    files: [sharedURL]
  )

  let plan = try await ManualStorageActionAdapter().makeDeletionPlan(
    context: DeletionPlanningContext(
      selectedInstallations: [selected],
      currentInventory: [selected, remaining],
      sources: [source]
    )
  )

  #expect(plan.operations.count == 1)
  #expect(plan.operations[0].fileURL == modelURL)
  #expect(plan.retainedDependencies.contains { $0.reason == .protectedIdentityOrSecret })
  #expect(plan.retainedDependencies.contains { $0.reason == .remainingReference })
}

@Test("Manual cleanup blocks a read-only source before building operations")
func manualCleanupBlocksReadOnlySource() async throws {
  let rootURL = temporaryActionDirectory()
  defer { try? FileManager.default.removeItem(at: rootURL) }
  try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  let modelURL = rootURL.appending(path: "model.gguf")
  try Data("model".utf8).write(to: modelURL)
  let source = actionSource(id: "read-only", providerID: .manual, rootURL: rootURL)
  let installation = try actionInstallation(
    id: "selected",
    providerID: .manual,
    source: source,
    files: [modelURL]
  )
  let adapter = ManualStorageActionAdapter(
    targetPolicy: DeletionTargetPolicy(volumeIsReadOnly: { _ in true })
  )

  await #expect(throws: StorageActionAdapterError.sourceUnavailable(source.id)) {
    try await adapter.makeDeletionPlan(
      context: DeletionPlanningContext(
        selectedInstallations: [installation],
        currentInventory: [installation],
        sources: [source]
      )
    )
  }
}

@Test("Manual retained dependencies are unique across a batch")
func manualRetainedDependenciesAreUnique() async throws {
  let rootURL = temporaryActionDirectory()
  defer { try? FileManager.default.removeItem(at: rootURL) }
  try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
  let firstModelURL = rootURL.appending(path: "first.gguf")
  let secondModelURL = rootURL.appending(path: "second.gguf")
  let secretURL = rootURL.appending(path: "id_ed25519")
  try Data("first".utf8).write(to: firstModelURL)
  try Data("second".utf8).write(to: secondModelURL)
  try Data("secret".utf8).write(to: secretURL)
  let source = actionSource(id: "manual", providerID: .manual, rootURL: rootURL)
  let first = try actionInstallation(
    id: "first",
    providerID: .manual,
    source: source,
    files: [firstModelURL, secretURL]
  )
  let second = try actionInstallation(
    id: "second",
    providerID: .manual,
    source: source,
    files: [secondModelURL, secretURL]
  )

  let plan = try await ManualStorageActionAdapter().makeDeletionPlan(
    context: DeletionPlanningContext(
      selectedInstallations: [first, second],
      currentInventory: [first, second],
      sources: [source]
    )
  )

  #expect(plan.retainedDependencies.count == 1)
  #expect(Set(plan.retainedDependencies[0].installationIDs) == [first.id, second.id])
}

@Test("Hugging Face retains a blob referenced by an unselected revision")
func huggingFaceRetainsSharedBlob() async throws {
  let fixture = try HuggingFaceActionFixture()
  defer { fixture.cleanup() }
  let plan = try await HuggingFaceStorageActionAdapter().makeDeletionPlan(
    context: DeletionPlanningContext(
      selectedInstallations: [fixture.firstInstallation],
      currentInventory: [fixture.firstInstallation, fixture.secondInstallation],
      sources: [fixture.source]
    )
  )

  #expect(plan.operations.contains { $0.fileURL == fixture.firstRevisionURL })
  #expect(!plan.operations.contains { $0.fileURL == fixture.blobURL })
  #expect(plan.retainedDependencies.contains { $0.reason == .remainingReference })
}

@Test("Hugging Face batch cleanup includes a blob after its final revision reference")
func huggingFaceBatchIncludesUnreferencedBlob() async throws {
  let fixture = try HuggingFaceActionFixture()
  defer { fixture.cleanup() }
  let inventory = [fixture.firstInstallation, fixture.secondInstallation]
  let plan = try await HuggingFaceStorageActionAdapter().makeDeletionPlan(
    context: DeletionPlanningContext(
      selectedInstallations: inventory,
      currentInventory: inventory,
      sources: [fixture.source]
    )
  )

  #expect(
    plan.operations.contains { $0.fileURL == fixture.blobURL },
    "Operation URLs: \(plan.operations.compactMap(\.fileURL)); blob: \(fixture.blobURL); retained: \(plan.retainedDependencies)"
  )
  #expect(plan.operations.contains { $0.fileURL == fixture.firstRevisionURL })
  #expect(plan.operations.contains { $0.fileURL == fixture.secondRevisionURL })
}

@Test("Ollama blocks loaded models and uses its provider request for deletion")
func ollamaBlocksLoadedModelsAndDeletesThroughProvider() async throws {
  let fixture = try OllamaActionFixture()
  defer { fixture.cleanup() }
  let loadedTransport = RecordingOllamaTransport(loadedModels: ["tiny:latest"])
  let loadedAdapter = OllamaStorageActionAdapter(transport: loadedTransport)

  await #expect(throws: StorageActionAdapterError.modelInUse("tiny:latest")) {
    try await loadedAdapter.makeDeletionPlan(context: fixture.context)
  }

  let transport = RecordingOllamaTransport()
  let adapter = OllamaStorageActionAdapter(transport: transport)
  let plan = try await adapter.makeDeletionPlan(context: fixture.context)
  #expect(plan.operations.count == 1)
  #expect(plan.operations[0].reversibility == .irreversible)
  guard case .provider(let request) = plan.operations[0].payload else {
    Issue.record("Expected an Ollama provider request")
    return
  }
  #expect(request.identifier == "tiny:latest")
  try await adapter.execute(request)
  #expect(await transport.deletedModels() == ["tiny:latest"])
}

private extension DeletionOperation {
  var fileURL: URL? {
    guard case .trash(let target) = payload else { return nil }
    return target.url
  }
}

private actor RecordingOllamaTransport: OllamaActionTransport {
  private let loadedModels: Set<String>
  private var deleted: [String] = []

  init(loadedModels: Set<String> = []) {
    self.loadedModels = loadedModels
  }

  func loadedModelNames() -> Set<String> { loadedModels }

  func deleteModel(named name: String) {
    deleted.append(name)
  }

  func deletedModels() -> [String] { deleted }
}

private struct HuggingFaceActionFixture {
  let rootURL: URL
  let blobURL: URL
  let firstRevisionURL: URL
  let secondRevisionURL: URL
  let source: ScanSource
  let firstInstallation: ModelInstallation
  let secondInstallation: ModelInstallation

  init() throws {
    rootURL = temporaryActionDirectory()
    let repositoryURL = rootURL.appending(path: "models--acme--tiny", directoryHint: .isDirectory)
    let blobsURL = repositoryURL.appending(path: "blobs", directoryHint: .isDirectory)
    blobURL = blobsURL.appending(path: "abc")
    firstRevisionURL = repositoryURL.appending(path: "snapshots/r1", directoryHint: .isDirectory)
    secondRevisionURL = repositoryURL.appending(path: "snapshots/r2", directoryHint: .isDirectory)
    let refsURL = repositoryURL.appending(path: "refs", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: firstRevisionURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: secondRevisionURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: refsURL, withIntermediateDirectories: true)
    try Data("blob".utf8).write(to: blobURL)
    let firstLink = firstRevisionURL.appending(path: "model.safetensors")
    let secondLink = secondRevisionURL.appending(path: "model.safetensors")
    try FileManager.default.createSymbolicLink(
      atPath: firstLink.path,
      withDestinationPath: "../../blobs/abc"
    )
    try FileManager.default.createSymbolicLink(
      atPath: secondLink.path,
      withDestinationPath: "../../blobs/abc"
    )
    try Data("r1\n".utf8).write(to: refsURL.appending(path: "main"))
    source = actionSource(id: "hf", providerID: .huggingFace, rootURL: rootURL)
    firstInstallation = try actionInstallation(
      id: "hf:r1",
      providerID: .huggingFace,
      source: source,
      rootURL: firstRevisionURL,
      files: [firstLink]
    )
    secondInstallation = try actionInstallation(
      id: "hf:r2",
      providerID: .huggingFace,
      source: source,
      rootURL: secondRevisionURL,
      files: [secondLink]
    )
  }

  func cleanup() { try? FileManager.default.removeItem(at: rootURL) }
}

private struct OllamaActionFixture {
  let rootURL: URL
  let source: ScanSource
  let installation: ModelInstallation

  init() throws {
    rootURL = temporaryActionDirectory()
    let manifestURL = rootURL.appending(
      path: "manifests/registry.ollama.ai/library/tiny/latest"
    )
    try FileManager.default.createDirectory(
      at: manifestURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("{}".utf8).write(to: manifestURL)
    source = actionSource(id: "ollama", providerID: .ollama, rootURL: rootURL)
    installation = try actionInstallation(
      id: "ollama:tiny",
      providerID: .ollama,
      source: source,
      rootURL: manifestURL,
      files: [manifestURL]
    )
  }

  var context: DeletionPlanningContext {
    DeletionPlanningContext(
      selectedInstallations: [installation],
      currentInventory: [installation],
      sources: [source]
    )
  }

  func cleanup() { try? FileManager.default.removeItem(at: rootURL) }
}

private func actionSource(id: String, providerID: ProviderID, rootURL: URL) -> ScanSource {
  ScanSource(
    id: id,
    displayName: id,
    providerID: providerID,
    rootURL: rootURL,
    accessState: .allowed,
    isEnabled: true
  )
}

private func actionInstallation(
  id: String,
  providerID: ProviderID,
  source: ScanSource,
  rootURL: URL? = nil,
  files: [URL]
) throws -> ModelInstallation {
  let artifacts = try files.map { url in
    let metadata = try FileMetadataReader().metadata(for: url)
    return Artifact(
      id: "\(id):\(url.lastPathComponent)",
      url: url,
      kind: .weights,
      logicalByteCount: metadata.logicalByteCount,
      allocatedByteCount: metadata.allocatedByteCount,
      physicalIdentifier: metadata.physicalIdentifier
    )
  }
  let identity = ModelIdentity(id: id, displayName: id)
  return ModelInstallation(
    id: id,
    identity: identity,
    variant: ModelVariant(id: "\(id):variant", identityID: id, format: .unknown),
    sourceID: source.id,
    providerID: providerID,
    rootURL: rootURL ?? files[0],
    state: .stored,
    artifacts: artifacts
  )
}

private func temporaryActionDirectory() -> URL {
  FileManager.default.temporaryDirectory.appending(
    path: "wtm-action-adapter-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
}
