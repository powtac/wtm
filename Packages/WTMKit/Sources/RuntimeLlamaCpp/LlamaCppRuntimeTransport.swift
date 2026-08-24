import Foundation
import WTMRuntime

public protocol LlamaCppRuntimeTransport: Sendable {
  func isHealthy(endpoint: URL) async throws -> Bool
  func complete(endpoint: URL, prompt: String) async throws -> String
}

public enum LlamaCppRuntimeTransportError: Error, Equatable, Sendable {
  case invalidEndpoint
  case invalidResponse
  case requestFailed(Int)
  case responseTooLarge
}

public actor LlamaCppHTTPRuntimeTransport: LlamaCppRuntimeTransport {
  private static let maximumResponseByteCount = 2 * 1_024 * 1_024

  private let session: URLSession

  public init(configuration: URLSessionConfiguration = .ephemeral) {
    let configuration = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 30
    configuration.connectionProxyDictionary = [:]
    session = URLSession(
      configuration: configuration,
      delegate: RejectRuntimeRedirectsDelegate(),
      delegateQueue: nil
    )
  }

  public func isHealthy(endpoint: URL) async throws -> Bool {
    try validate(endpoint)
    let (data, response) = try await session.data(
      from: endpoint.appending(path: "health")
    )
    guard let response = response as? HTTPURLResponse else {
      throw LlamaCppRuntimeTransportError.invalidResponse
    }
    if response.statusCode == 503 { return false }
    guard response.statusCode == 200 else {
      throw LlamaCppRuntimeTransportError.requestFailed(response.statusCode)
    }
    guard data.count <= Self.maximumResponseByteCount else {
      throw LlamaCppRuntimeTransportError.responseTooLarge
    }
    return (try? JSONDecoder().decode(HealthResponse.self, from: data).status) == "ok"
  }

  public func complete(endpoint: URL, prompt: String) async throws -> String {
    try validate(endpoint)
    var request = URLRequest(url: endpoint.appending(path: "completion"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(
      CompletionRequest(prompt: prompt, nPredict: 1, stream: false, temperature: 0)
    )
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw LlamaCppRuntimeTransportError.invalidResponse
    }
    guard response.statusCode == 200 else {
      throw LlamaCppRuntimeTransportError.requestFailed(response.statusCode)
    }
    guard data.count <= Self.maximumResponseByteCount else {
      throw LlamaCppRuntimeTransportError.responseTooLarge
    }
    return try JSONDecoder().decode(CompletionResponse.self, from: data).content
  }

  private func validate(_ endpoint: URL) throws {
    do {
      try LoopbackEndpointPolicy().validate(endpoint)
    } catch {
      throw LlamaCppRuntimeTransportError.invalidEndpoint
    }
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

private struct HealthResponse: Decodable {
  let status: String
}

private struct CompletionRequest: Encodable {
  let prompt: String
  let nPredict: Int
  let stream: Bool
  let temperature: Double

  enum CodingKeys: String, CodingKey {
    case prompt
    case nPredict = "n_predict"
    case stream
    case temperature
  }
}

private struct CompletionResponse: Decodable {
  let content: String
}
