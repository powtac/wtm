import Foundation
import WTMAdapterContracts
import WTMDomain

public protocol OllamaActionTransport: Sendable {
  func loadedModelNames() async throws -> Set<String>
  func deleteModel(named name: String) async throws
}

public enum OllamaActionTransportError: Error, Equatable, Sendable {
  case endpointMustBeLoopback
  case invalidResponse
  case requestFailed(Int)
}

public actor OllamaHTTPActionTransport: OllamaActionTransport {
  private let baseURL: URL
  private let session: URLSession

  public init(baseURL: URL, session: URLSession = .shared) throws {
    guard baseURL.scheme == "http",
      ["127.0.0.1", "localhost", "::1"].contains(baseURL.host?.lowercased() ?? "")
    else {
      throw OllamaActionTransportError.endpointMustBeLoopback
    }
    self.baseURL = baseURL
    self.session = session
  }

  public func loadedModelNames() async throws -> Set<String> {
    let url = baseURL.appending(path: "api/ps")
    let (data, response) = try await session.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OllamaActionTransportError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw OllamaActionTransportError.requestFailed(httpResponse.statusCode)
    }
    let payload = try JSONDecoder().decode(LoadedModelsResponse.self, from: data)
    return Set(payload.models.compactMap { $0.name ?? $0.model }.map(normalizedModelName))
  }

  public func deleteModel(named name: String) async throws {
    var request = URLRequest(url: baseURL.appending(path: "api/delete"))
    request.httpMethod = "DELETE"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(DeleteModelRequest(model: name))
    let (_, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OllamaActionTransportError.invalidResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
      throw OllamaActionTransportError.requestFailed(httpResponse.statusCode)
    }
  }
}

public struct OllamaStorageActionAdapter: StorageActionAdapter {
  public let id = ProviderID.ollama
  public let displayName = "Ollama"

  private let transport: any OllamaActionTransport

  public init(transport: any OllamaActionTransport) {
    self.transport = transport
  }

  public init(baseURL: URL, session: URLSession = .shared) throws {
    transport = try OllamaHTTPActionTransport(baseURL: baseURL, session: session)
  }

  public func makeDeletionPlan(context: DeletionPlanningContext) async throws
    -> ProviderDeletionPlan
  {
    let selected = context.selectedInstallations.filter { $0.providerID == id }
    guard selected.count == context.selectedInstallations.count, !selected.isEmpty else {
      throw StorageActionAdapterError.invalidSelection
    }

    let loadedModels: Set<String>
    do {
      loadedModels = try await transport.loadedModelNames()
    } catch {
      throw StorageActionAdapterError.providerUnavailable
    }
    let selectedIDs = Set(selected.map(\.id))
    let remainingPhysicalIDs = Set(
      context.currentInventory
        .filter { !selectedIDs.contains($0.id) }
        .flatMap(\.artifacts)
        .compactMap(\.physicalIdentifier)
    )
    var operations: [DeletionOperation] = []
    var retainedByID: [String: RetainedDeletionDependency] = [:]

    for installation in selected {
      guard let source = context.source(for: installation.sourceID), source.isEnabled,
        source.accessState == .allowed
      else {
        throw StorageActionAdapterError.sourceUnavailable(installation.sourceID)
      }
      let modelName = try modelName(for: installation, source: source)
      guard !isLoaded(modelName, loadedModels: loadedModels) else {
        throw StorageActionAdapterError.modelInUse(modelName)
      }

      var reclaimableByteCount: Int64 = 0
      var countedPhysicalIDs: Set<String> = []
      for artifact in installation.artifacts {
        guard let physicalIdentifier = artifact.physicalIdentifier else {
          mergeRetained(
            id: "ollama:retained:unknown:\(artifact.url.standardizedFileURL.path)",
            artifact: artifact,
            installationID: installation.id,
            reason: .unknownOwnership,
            into: &retainedByID
          )
          continue
        }
        guard !remainingPhysicalIDs.contains(physicalIdentifier) else {
          mergeRetained(
            id: "ollama:retained:shared:\(physicalIdentifier)",
            artifact: artifact,
            installationID: installation.id,
            reason: .remainingReference,
            into: &retainedByID
          )
          continue
        }
        if countedPhysicalIDs.insert(physicalIdentifier).inserted {
          reclaimableByteCount += artifact.allocatedByteCount
        }
      }

      operations.append(
        DeletionOperation(
          id: "ollama:delete:\(normalizedModelName(modelName))",
          providerID: id,
          installationIDs: [installation.id],
          reversibility: .irreversible,
          expectedReclaimableByteCount: reclaimableByteCount,
          payload: .provider(
            ProviderDeletionRequest(kind: .ollamaModel, identifier: modelName)
          )
        )
      )
    }

    return ProviderDeletionPlan(
      providerID: id,
      models: selected.map(Self.summary),
      operations: operations,
      retainedDependencies: Array(retainedByID.values),
      warnings: [.freeSpaceIsEstimated]
    )
  }

  public func execute(_ request: ProviderDeletionRequest) async throws {
    guard request.kind == .ollamaModel else {
      throw StorageActionAdapterError.unsupportedProviderRequest
    }
    do {
      try await transport.deleteModel(named: request.identifier)
    } catch {
      throw StorageActionAdapterError.providerRequestFailed
    }
  }

  private func modelName(for installation: ModelInstallation, source: ScanSource) throws -> String {
    let manifestPath = installation.rootURL.standardizedFileURL.path
    let sourcePath = source.rootURL.standardizedFileURL.path
    guard manifestPath.hasPrefix(sourcePath + "/") else {
      throw StorageActionAdapterError.pathOutsideSource
    }
    let relativeComponents = manifestPath.dropFirst(sourcePath.count).split(separator: "/")
    guard let manifestsIndex = relativeComponents.firstIndex(of: "manifests") else {
      throw StorageActionAdapterError.invalidSelection
    }
    let location = Array(relativeComponents.dropFirst(manifestsIndex + 1)).map(String.init)
    guard location.count >= 4, let tag = location.last else {
      throw StorageActionAdapterError.invalidSelection
    }
    var modelComponents = Array(location.dropFirst().dropLast())
    if modelComponents.first == "library" { modelComponents.removeFirst() }
    guard !modelComponents.isEmpty else { throw StorageActionAdapterError.invalidSelection }
    return modelComponents.joined(separator: "/") + ":" + tag
  }

  private func isLoaded(_ modelName: String, loadedModels: Set<String>) -> Bool {
    let normalized = normalizedModelName(modelName)
    let withoutLatest =
      normalized.hasSuffix(":latest")
      ? String(normalized.dropLast(":latest".count))
      : normalized
    return loadedModels.contains(normalized) || loadedModels.contains(withoutLatest)
  }

  private func mergeRetained(
    id: String,
    artifact: Artifact,
    installationID: ModelInstallation.ID,
    reason: RetainedDependencyReason,
    into dependencies: inout [String: RetainedDeletionDependency]
  ) {
    let existing = dependencies[id]
    dependencies[id] = RetainedDeletionDependency(
      id: id,
      displayName: artifact.url.lastPathComponent,
      allocatedByteCount: max(existing?.allocatedByteCount ?? 0, artifact.allocatedByteCount),
      reason: reason,
      installationIDs: Array(Set(existing?.installationIDs ?? []).union([installationID]))
    )
  }

  private static func summary(_ installation: ModelInstallation) -> DeletionModelSummary {
    DeletionModelSummary(
      id: installation.id,
      displayName: installation.identity.displayName,
      providerID: installation.providerID,
      sourceID: installation.sourceID,
      artifactCount: installation.artifacts.count,
      allocatedByteCount: installation.allocatedByteCount
    )
  }
}

private struct LoadedModelsResponse: Decodable {
  let models: [LoadedModel]
}

private struct LoadedModel: Decodable {
  let name: String?
  let model: String?
}

private struct DeleteModelRequest: Encodable {
  let model: String
}

private func normalizedModelName(_ name: String) -> String {
  name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
