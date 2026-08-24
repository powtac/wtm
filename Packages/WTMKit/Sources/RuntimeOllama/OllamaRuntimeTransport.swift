import Foundation
import WTMRuntime

public protocol OllamaRuntimeTransport: Sendable {
  func availableModelNames() async throws -> Set<String>
  func runningModelNames() async throws -> Set<String>
  func generate(model: String, prompt: String) async throws -> String
}

public enum OllamaRuntimeTransportError: Error, Equatable, Sendable {
  case invalidEndpoint
  case invalidResponse
  case requestFailed(Int)
  case responseTooLarge
}

public actor OllamaHTTPRuntimeTransport: OllamaRuntimeTransport {
  private static let maximumResponseByteCount = 8 * 1_024 * 1_024

  private let baseURL: URL
  private let session: URLSession

  public init(
    baseURL: URL,
    configuration: URLSessionConfiguration = .ephemeral
  ) throws {
    do {
      try LoopbackEndpointPolicy().validate(baseURL)
    } catch {
      throw OllamaRuntimeTransportError.invalidEndpoint
    }
    let configuration = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 30
    configuration.connectionProxyDictionary = [:]
    self.baseURL = baseURL
    session = URLSession(
      configuration: configuration,
      delegate: RejectRuntimeRedirectsDelegate(),
      delegateQueue: nil
    )
  }

  public func availableModelNames() async throws -> Set<String> {
    let data = try await responseData(for: URLRequest(url: baseURL.appending(path: "api/tags")))
    let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
    return Set(response.models.compactMap { $0.name ?? $0.model }.map(normalizedModelName))
  }

  public func runningModelNames() async throws -> Set<String> {
    let data = try await responseData(for: URLRequest(url: baseURL.appending(path: "api/ps")))
    let response = try JSONDecoder().decode(ModelListResponse.self, from: data)
    return Set(response.models.compactMap { $0.name ?? $0.model }.map(normalizedModelName))
  }

  public func generate(model: String, prompt: String) async throws -> String {
    var request = URLRequest(url: baseURL.appending(path: "api/generate"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      GenerateRequest(model: model, prompt: prompt, stream: false, options: .init(numPredict: 1))
    )
    let data = try await responseData(for: request)
    return try JSONDecoder().decode(GenerateResponse.self, from: data).response
  }

  private func responseData(for request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw OllamaRuntimeTransportError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw OllamaRuntimeTransportError.requestFailed(response.statusCode)
    }
    guard data.count <= Self.maximumResponseByteCount else {
      throw OllamaRuntimeTransportError.responseTooLarge
    }
    return data
  }
}

private final class RejectRuntimeRedirectsDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

private struct ModelListResponse: Decodable {
  let models: [ListedModel]
}

private struct ListedModel: Decodable {
  let name: String?
  let model: String?
}

private struct GenerateRequest: Encodable {
  let model: String
  let prompt: String
  let stream: Bool
  let options: GenerateOptions
}

private struct GenerateOptions: Encodable {
  let numPredict: Int

  enum CodingKeys: String, CodingKey {
    case numPredict = "num_predict"
  }
}

private struct GenerateResponse: Decodable {
  let response: String
}

private func normalizedModelName(_ name: String) -> String {
  name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
