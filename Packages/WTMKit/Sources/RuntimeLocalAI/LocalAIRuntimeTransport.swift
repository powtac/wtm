import Foundation
import WTMRuntime

public protocol LocalAIRuntimeTransport: Sendable {
  func health() async throws
  func models() async throws -> Set<String>
  func generate(model: String, prompt: String) async throws -> String
}

public enum LocalAITransportError: Error { case invalidResponse, tooLarge, http(Int) }

public actor LocalAIHTTPTransport: LocalAIRuntimeTransport {
  private let endpoint: URL
  private let session: URLSession

  public init(endpoint: URL, configuration: URLSessionConfiguration = .ephemeral) throws {
    try LoopbackEndpointPolicy().validate(endpoint)
    guard ["", "/"].contains(endpoint.path) else { throw LocalAITransportError.invalidResponse }
    self.endpoint = endpoint
    let config = configuration.copy() as? URLSessionConfiguration ?? .ephemeral
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 30
    config.waitsForConnectivity = false
    config.connectionProxyDictionary = [:]
    config.urlCredentialStorage = nil
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.httpAdditionalHeaders = nil
    config.urlCache = nil
    session = URLSession(
      configuration: config, delegate: LocalAIRedirectPolicy(), delegateQueue: nil)
  }

  public func health() async throws {
    _ = try await data(URLRequest(url: endpoint.appending(path: "readyz")))
  }

  public func models() async throws -> Set<String> {
    struct Model: Decodable { let id: String }
    struct Response: Decodable { let data: [Model] }
    let response = try await data(URLRequest(url: endpoint.appending(path: "v1/models")))
    return Set(try JSONDecoder().decode(Response.self, from: response).data.map(\.id))
  }

  public func generate(model: String, prompt: String) async throws -> String {
    var request = URLRequest(url: endpoint.appending(path: "v1/chat/completions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "model": model, "messages": [["role": "user", "content": prompt]],
      "max_tokens": 1, "stream": false,
    ])
    struct Message: Decodable { let content: String }
    struct Choice: Decodable { let message: Message }
    struct Response: Decodable { let choices: [Choice] }
    let response = try await data(request)
    guard
      let content = try JSONDecoder().decode(Response.self, from: response).choices.first?.message
        .content,
      !content.isEmpty
    else { throw LocalAITransportError.invalidResponse }
    return String(content.prefix(200))
  }

  private func data(_ request: URLRequest) async throws -> Data {
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let response = response as? HTTPURLResponse else {
      throw LocalAITransportError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw LocalAITransportError.http(response.statusCode)
    }
    let limit = 1_048_576
    guard response.expectedContentLength <= limit else { throw LocalAITransportError.tooLarge }
    var data = Data()
    for try await byte in bytes {
      guard data.count < limit else { throw LocalAITransportError.tooLarge }
      data.append(byte)
    }
    return data
  }
}

private final class LocalAIRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
