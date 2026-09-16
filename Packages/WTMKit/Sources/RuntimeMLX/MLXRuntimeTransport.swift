import Foundation
import WTMRuntime

public protocol MLXRuntimeTransport: Sendable {
  func health(_ endpoint: URL) async throws
  func complete(_ endpoint: URL, prompt: String) async throws -> String
}

public actor MLXHTTPRuntimeTransport: MLXRuntimeTransport {
  private let session: URLSession
  public init(configuration: URLSessionConfiguration = .ephemeral) {
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
    session = URLSession(configuration: config, delegate: MLXRedirectPolicy(), delegateQueue: nil)
  }

  public func health(_ endpoint: URL) async throws {
    struct Response: Decodable { let status: String; let `protocol`: Int }
    let data = try await request(endpoint, path: "health")
    let response = try JSONDecoder().decode(Response.self, from: data)
    guard response.status == "ok", response.protocol == 1 else {
      throw MLXHTTPError.invalidResponse
    }
  }

  public func complete(_ endpoint: URL, prompt: String) async throws -> String {
    guard !prompt.isEmpty, prompt.utf8.count <= 1024 else { throw MLXHTTPError.invalidResponse }
    let body = try JSONSerialization.data(withJSONObject: ["prompt": prompt])
    let data = try await request(endpoint, path: "completion", body: body)
    struct Response: Decodable { let content: String; let tokens_predicted: Int }
    let response = try JSONDecoder().decode(Response.self, from: data)
    guard response.tokens_predicted == 1 else { throw MLXHTTPError.invalidResponse }
    return String(response.content.prefix(200))
  }

  private func request(_ endpoint: URL, path: String, body: Data? = nil) async throws -> Data {
    try LoopbackEndpointPolicy().validate(endpoint)
    guard ["", "/"].contains(endpoint.path) else { throw MLXHTTPError.invalidResponse }
    var request = URLRequest(url: endpoint.appending(path: path))
    if let body {
      request.httpMethod = "POST"
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      http.expectedContentLength <= 65536
    else { throw MLXHTTPError.invalidResponse }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 65536 else { throw MLXHTTPError.invalidResponse }
      data.append(byte)
    }
    return data
  }
}

private enum MLXHTTPError: Error { case invalidResponse }
private final class MLXRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}
