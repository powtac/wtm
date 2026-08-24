import ActionHuggingFace
import ActionManual
import ActionOllama
import AdapterHuggingFace
import AdapterManual
import AdapterOllama
import Foundation
import RuntimeLlamaCpp
import RuntimeOllama
import WTMActions
import WTMAdapterContracts
import WTMInventory
import WTMPersistence
import WTMRuntime

@MainActor
enum AppComposition {
  static func makeInventoryViewModel() -> InventoryViewModel {
    let registry = try? AdapterRegistry(adapters: [
      OllamaStorageAdapter(),
      try HuggingFaceStorageAdapter(),
      ManualFolderAdapter(),
    ])
    let coordinator = registry.map { InventoryCoordinator(registry: $0) }
    let homeDirectory: URL
    #if DEBUG
      homeDirectory =
        ProcessInfo.processInfo.environment["WTM_UI_TEST_HOME_DIRECTORY"]
        .map { URL(filePath: $0, directoryHint: .isDirectory) }
        ?? FileManager.default.homeDirectoryForCurrentUser
    #else
      homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    #endif
    let sources = DefaultSourceCatalog().suggestions(homeDirectory: homeDirectory)
    let applicationSupportDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appending(
      path: ProcessInfo.processInfo.environment["WTM_SETTINGS_NAMESPACE"]
        ?? Bundle.main.bundleIdentifier ?? "de.powtac.whatthemodel",
      directoryHint: .isDirectory
    )
    var actionAdapters: [any StorageActionAdapter] = [
      HuggingFaceStorageActionAdapter(),
      ManualStorageActionAdapter(),
    ]
    let ollamaURL = URL(string: "http://127.0.0.1:11434")
    if let ollamaURL,
      let ollamaActionAdapter = try? OllamaStorageActionAdapter(baseURL: ollamaURL)
    {
      actionAdapters.append(ollamaActionAdapter)
    }
    let actionRegistry = try? StorageActionAdapterRegistry(adapters: actionAdapters)
    let actionExecutor = actionRegistry.map { registry in
      ActionExecutor(
        registry: registry,
        trashMover: SystemTrashMover(),
        auditStore: JSONActionAuditStore(
          auditURL: applicationSupportDirectory.appending(
            path: "action-audit.json",
            directoryHint: .notDirectory
          )
        )
      )
    }
    var runtimeAdapters: [any RuntimeAdapter] = [LlamaCppRuntimeAdapter()]
    if let ollamaURL, let ollamaRuntimeAdapter = try? OllamaRuntimeAdapter(endpoint: ollamaURL) {
      runtimeAdapters.append(ollamaRuntimeAdapter)
    }
    let runtimeRegistry = try? RuntimeAdapterRegistry(adapters: runtimeAdapters)
    let runtimeBroker = runtimeRegistry.map { RuntimeBroker(registry: $0) }
    let initialToolDefinitions = LlamaCppToolConvention().discoveredDefinition().map { [$0] } ?? []
    return InventoryViewModel(
      coordinator: coordinator,
      initialSources: sources,
      sourceSettingsStore: JSONSourceSettingsStore(
        settingsURL: applicationSupportDirectory.appending(
          path: "source-settings.json",
          directoryHint: .notDirectory
        )
      ),
      folderSelector: MacFolderSelector(),
      fileRevealer: MacFileRevealer(),
      volumeCatalog: MacVolumeCatalog(),
      actionExecutor: actionExecutor,
      runtimeRegistry: runtimeRegistry,
      runtimeBroker: runtimeBroker,
      toolSettingsStore: JSONToolSettingsStore(
        settingsURL: applicationSupportDirectory.appending(
          path: "tool-settings.json",
          directoryHint: .notDirectory
        )
      ),
      initialToolDefinitions: initialToolDefinitions,
      executableSelector: MacExecutableSelector()
    )
  }
}
