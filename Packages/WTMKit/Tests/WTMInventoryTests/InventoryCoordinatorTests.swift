import Foundation
import Testing
import WTMAdapterContracts

@testable import WTMDomain
@testable import WTMInventory

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

private struct FixtureAdapter: StorageProviderAdapter {
  static let providerID = ProviderID(rawValue: "fixture")
  let id = providerID
  let displayName = "Fixture"

  func scan(source: ScanSource) async -> AdapterScanResult {
    AdapterScanResult(source: source, installations: [])
  }
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
  let identity = ModelIdentity(id: "identity", displayName: "Fixture")
  let variant = ModelVariant(id: "variant", identityID: identity.id, format: .gguf)
  return ModelInstallation(
    id: id,
    identity: identity,
    variant: variant,
    sourceID: "source",
    providerID: .manual,
    rootURL: artifact.url,
    state: .stored,
    artifacts: [artifact]
  )
}
