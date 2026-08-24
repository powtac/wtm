import Foundation
import Synchronization
import Testing

@testable import RuntimeLlamaCpp
@testable import RuntimeOllama

private struct CapturedRuntimeRequest: Sendable {
  let method: String
  let path: String
  let body: Data
}

private enum RuntimeHTTPFixtureError: Error {
  case missingHandler
  case invalidURL
  case invalidResponse
}

private final class RuntimeURLProtocolStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with _: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw RuntimeHTTPFixtureError.missingHandler }
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct RuntimeHTTPContractTests {
  @Test("Ollama runtime HTTP uses tags, ps, and a bounded non-streaming generate request")
  func ollamaRuntimeHTTPContract() async throws {
    let captured = Mutex<[CapturedRuntimeRequest]>([])
    RuntimeURLProtocolStub.handler = { request in
      captured.withLock {
        $0.append(
          CapturedRuntimeRequest(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            body: requestBody(request)
          )
        )
      }
      let body: Data
      switch request.url?.path {
      case "/api/tags": body = Data(#"{"models":[{"name":"tiny:latest"}]}"#.utf8)
      case "/api/ps": body = Data(#"{"models":[]}"#.utf8)
      case "/api/generate": body = Data(#"{"response":"O","done":true}"#.utf8)
      default: body = Data()
      }
      return (try response(for: request, status: 200), body)
    }
    defer { RuntimeURLProtocolStub.handler = nil }
    let transport = try OllamaHTTPRuntimeTransport(
      baseURL: runtimeHTTPURL(port: 11_434),
      configuration: stubConfiguration()
    )

    #expect(try await transport.availableModelNames() == ["tiny:latest"])
    #expect(try await transport.runningModelNames().isEmpty)
    #expect(try await transport.generate(model: "tiny:latest", prompt: "OK?") == "O")

    let requests = captured.withLock { $0 }
    #expect(requests.map(\.path) == ["/api/tags", "/api/ps", "/api/generate"])
    #expect(requests.map(\.method) == ["GET", "GET", "POST"])
    let generate = try #require(
      JSONSerialization.jsonObject(with: requests[2].body) as? [String: Any]
    )
    #expect(generate["model"] as? String == "tiny:latest")
    #expect(generate["stream"] as? Bool == false)
    #expect(generate["keep_alive"] == nil)
    let options = try #require(generate["options"] as? [String: Any])
    #expect(options["num_predict"] as? Int == 1)
  }

  @Test("llama.cpp HTTP uses official health and one-token completion contracts")
  func llamaCppRuntimeHTTPContract() async throws {
    let captured = Mutex<[CapturedRuntimeRequest]>([])
    RuntimeURLProtocolStub.handler = { request in
      captured.withLock {
        $0.append(
          CapturedRuntimeRequest(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            body: requestBody(request)
          )
        )
      }
      let body =
        request.url?.path == "/health"
        ? Data(#"{"status":"ok"}"#.utf8) : Data(#"{"content":"O"}"#.utf8)
      return (try response(for: request, status: 200), body)
    }
    defer { RuntimeURLProtocolStub.handler = nil }
    let transport = LlamaCppHTTPRuntimeTransport(configuration: stubConfiguration())
    let endpoint = runtimeHTTPURL(port: 20_001)

    #expect(try await transport.isHealthy(endpoint: endpoint))
    #expect(try await transport.complete(endpoint: endpoint, prompt: "OK?") == "O")

    let requests = captured.withLock { $0 }
    #expect(requests.map(\.path) == ["/health", "/completion"])
    #expect(requests.map(\.method) == ["GET", "POST"])
    let completion = try #require(
      JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any]
    )
    #expect(completion["prompt"] as? String == "OK?")
    #expect(completion["n_predict"] as? Int == 1)
    #expect(completion["stream"] as? Bool == false)
    #expect(completion["temperature"] as? Int == 0)
  }

  @Test("Runtime HTTP transports reject non-loopback endpoints")
  func runtimeHTTPRejectsRemoteEndpoints() async {
    #expect(throws: OllamaRuntimeTransportError.invalidEndpoint) {
      _ = try OllamaHTTPRuntimeTransport(
        baseURL: runtimeHTTPURL(host: "example.com", port: 11_434),
        configuration: stubConfiguration()
      )
    }
    let transport = LlamaCppHTTPRuntimeTransport(configuration: stubConfiguration())
    await #expect(throws: LlamaCppRuntimeTransportError.invalidEndpoint) {
      _ = try await transport.isHealthy(
        endpoint: runtimeHTTPURL(host: "example.com", port: 20_001)
      )
    }
  }
}

private func stubConfiguration() -> URLSessionConfiguration {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [RuntimeURLProtocolStub.self]
  return configuration
}

private func runtimeHTTPURL(host: String = "127.0.0.1", port: Int) -> URL {
  var components = URLComponents()
  components.scheme = "http"
  components.host = host
  components.port = port
  guard let url = components.url else { preconditionFailure("Valid test endpoint") }
  return url
}

private func response(for request: URLRequest, status: Int) throws -> HTTPURLResponse {
  guard let url = request.url else { throw RuntimeHTTPFixtureError.invalidURL }
  guard
    let response = HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"]
    )
  else { throw RuntimeHTTPFixtureError.invalidResponse }
  return response
}

private func requestBody(_ request: URLRequest) -> Data {
  if let body = request.httpBody { return body }
  guard let stream = request.httpBodyStream else { return Data() }
  stream.open()
  defer { stream.close() }
  var output = Data()
  var buffer = [UInt8](repeating: 0, count: 1_024)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    guard count > 0 else { break }
    output.append(buffer, count: count)
  }
  return output
}
