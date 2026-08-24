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
    let coordinator = registry.map(InventoryCoordinator.init(registry:))
    let sources = DefaultSourceCatalog().suggestions(
      homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
    return InventoryViewModel(
      coordinator: coordinator,
      initialSources: sources,
      folderSelector: MacFolderSelector(),
      fileRevealer: MacFileRevealer()
    )
  }
}
