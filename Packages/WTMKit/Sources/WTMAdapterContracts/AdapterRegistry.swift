import WTMDomain

public enum AdapterRegistryError: Error, Equatable, Sendable {
  case duplicateProvider(ProviderID)
}

/// Immutable registry used by the composition root to inject concrete adapters.
public struct AdapterRegistry: Sendable {
  private let adaptersByID: [ProviderID: any StorageProviderAdapter]

  public init(adapters: [any StorageProviderAdapter]) throws {
    var registered: [ProviderID: any StorageProviderAdapter] = [:]
    for adapter in adapters {
      guard registered[adapter.id] == nil else {
        throw AdapterRegistryError.duplicateProvider(adapter.id)
      }
      registered[adapter.id] = adapter
    }
    adaptersByID = registered
  }

  public func adapter(for providerID: ProviderID) -> (any StorageProviderAdapter)? {
    adaptersByID[providerID]
  }

  public var providerIDs: Set<ProviderID> {
    Set(adaptersByID.keys)
  }
}
