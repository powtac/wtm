import WTMDomain

public enum StorageActionAdapterRegistryError: Error, Equatable, Sendable {
  case duplicateProvider(ProviderID)
}

/// Immutable registry for destructive capabilities, separate from read-only discovery.
public struct StorageActionAdapterRegistry: Sendable {
  private let adaptersByID: [ProviderID: any StorageActionAdapter]

  public init(adapters: [any StorageActionAdapter]) throws {
    var registered: [ProviderID: any StorageActionAdapter] = [:]
    for adapter in adapters {
      guard registered[adapter.id] == nil else {
        throw StorageActionAdapterRegistryError.duplicateProvider(adapter.id)
      }
      registered[adapter.id] = adapter
    }
    adaptersByID = registered
  }

  public func adapter(for providerID: ProviderID) -> (any StorageActionAdapter)? {
    adaptersByID[providerID]
  }

  public var providerIDs: Set<ProviderID> { Set(adaptersByID.keys) }
}
