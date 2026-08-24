import AdapterHuggingFace
import AdapterManual
import AdapterOllama
import Foundation
import WTMAdapterContracts
import WTMInventory

@MainActor
enum AppComposition {
  static func makeInventoryViewModel() -> InventoryViewModel {
    let registry = try? AdapterRegistry(adapters: [
      OllamaStorageAdapter(),
      HuggingFaceStorageAdapter(),
      ManualFolderAdapter(),
    ])
    let coordinator = registry.map { InventoryCoordinator(registry: $0) }
    let sources = DefaultSourceCatalog().suggestions(
      homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
    let applicationSupportURL = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appending(
      path: ProcessInfo.processInfo.environment["WTM_SETTINGS_NAMESPACE"]
        ?? Bundle.main.bundleIdentifier ?? "de.powtac.whatthemodel",
      directoryHint: .isDirectory
    )
    .appending(path: "source-settings.json", directoryHint: .notDirectory)
    return InventoryViewModel(
      coordinator: coordinator,
      initialSources: sources,
      sourceSettingsStore: JSONSourceSettingsStore(settingsURL: applicationSupportURL),
      folderSelector: MacFolderSelector(),
      fileRevealer: MacFileRevealer(),
      volumeCatalog: MacVolumeCatalog()
    )
  }
}
