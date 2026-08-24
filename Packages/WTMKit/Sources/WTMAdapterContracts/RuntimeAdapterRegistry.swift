import WTMDomain

public enum RuntimeAdapterRegistryError: Error, Equatable, Sendable {
  case duplicateRuntime(RuntimeAdapterID)
}

public struct RuntimeAdapterRegistry: Sendable {
  private let adaptersByID: [RuntimeAdapterID: any RuntimeAdapter]

  public init(adapters: [any RuntimeAdapter]) throws {
    var registered: [RuntimeAdapterID: any RuntimeAdapter] = [:]
    for adapter in adapters {
      guard registered[adapter.id] == nil else {
        throw RuntimeAdapterRegistryError.duplicateRuntime(adapter.id)
      }
      registered[adapter.id] = adapter
    }
    adaptersByID = registered
  }

  public func adapter(for id: RuntimeAdapterID) -> (any RuntimeAdapter)? {
    adaptersByID[id]
  }

  public var runtimeIDs: Set<RuntimeAdapterID> { Set(adaptersByID.keys) }
}
