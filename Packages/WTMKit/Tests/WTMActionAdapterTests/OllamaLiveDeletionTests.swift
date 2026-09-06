import ActionOllama
import AdapterOllama
import Foundation
import Testing
import WTMActions
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

@Test(
  "Real Ollama deletion removes the disposable smollm2:135m model",
  .enabled(if: ProcessInfo.processInfo.environment["WTM_TEST_OLLAMA_DELETION"] == "1")
)
func realOllamaDeletion() async throws {
  let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ollama/models")
  let source = ScanSource(
    id: "live-ollama", displayName: "Ollama", providerID: .ollama, rootURL: root,
    rootIdentity: try SourceRootPolicy().capture(rootURL: root),
    accessState: .allowed, isEnabled: true
  )
  let manifest = root.appending(path: "manifests/registry.ollama.ai/library/smollm2/135m")
  let scanner = OllamaStorageAdapter()
  let before = await scanner.scan(source: source)
  let model = try #require(before.installations.first { $0.rootURL == manifest })
  #expect(model.state == .stored)
  let otherModels = Set(before.installations.filter { $0.id != model.id }.map(\.id))
  let endpoint = URL(string: "http://127.0.0.1:11434")!
  let adapter = try OllamaStorageActionAdapter(baseURL: endpoint)
  let audit = InMemoryActionAuditStore()
  let executor = ActionExecutor(
    registry: try StorageActionAdapterRegistry(adapters: [adapter]),
    trashMover: SystemTrashMover(), auditStore: audit
  )
  let plan = try await executor.prepareDeletion(
    installationIDs: [model.id], currentInventory: before.installations, sources: [source]
  )
  #expect(plan.operations.count == 1)
  #expect(plan.requiresIrreversibleConfirmation)
  let report = try await executor.execute(
    plan, currentInventory: before.installations, sources: [source],
    confirmedIrreversible: true
  )
  #expect(report.status == .succeeded)
  #expect(report.operationResults.allSatisfy { $0.status == .succeeded })
  #expect(!FileManager.default.fileExists(atPath: manifest.path))
  let after = await scanner.scan(source: source)
  #expect(!after.installations.contains { $0.id == model.id })
  #expect(otherModels.isSubset(of: Set(after.installations.map(\.id))))
  let (data, response) = try await URLSession.shared.data(
    from: endpoint.appending(path: "api/tags")
  )
  #expect((response as? HTTPURLResponse)?.statusCode == 200)
  let tags = try JSONDecoder().decode(LiveOllamaTags.self, from: data)
  #expect(!tags.models.contains { $0.name == "smollm2:135m" })
  #expect(await audit.entries().last?.status == .succeeded)
}

private struct LiveOllamaTags: Decodable {
  let models: [Model]
  struct Model: Decodable {
    let name: String
  }
}
