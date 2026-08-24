import WTMDomain

public enum ClientAdapterRegistryError: Error, Equatable, Sendable {
  case duplicateClient(ClientAdapterID)
}

public struct ClientAdapterRegistry: Sendable {
  private let adaptersByID: [ClientAdapterID: any ClientAdapter]

  public init(adapters: [any ClientAdapter]) throws {
    var registered: [ClientAdapterID: any ClientAdapter] = [:]
    for adapter in adapters {
      guard registered[adapter.id] == nil else {
        throw ClientAdapterRegistryError.duplicateClient(adapter.id)
      }
      registered[adapter.id] = adapter
    }
    adaptersByID = registered
  }

  public func adapter(for id: ClientAdapterID) -> (any ClientAdapter)? {
    adaptersByID[id]
  }

  public var clientIDs: Set<ClientAdapterID> { Set(adaptersByID.keys) }
}
