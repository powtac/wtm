import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMRuntime

public struct UnslothClientAdapter: ClientAdapter {
  public let id = ClientAdapterID.unsloth
  public let displayName = "Unsloth Studio"
  public let version = "1"

  private let pythonURL: URL?
  private let scriptURL: URL?
  private let environment: [String: String]
  private let port: UInt16
  private let inspector: ExecutableInspector

  public init(
    pythonURL: URL?,
    scriptURL: URL?,
    environment: [String: String],
    port: UInt16 = 8_888,
    inspector: ExecutableInspector = ExecutableInspector()
  ) {
    self.pythonURL = pythonURL
    self.scriptURL = scriptURL
    self.environment = environment
    self.port = port
    self.inspector = inspector
  }

  public static func discovered(homeDirectory: URL) -> UnslothClientAdapter {
    let fileManager = FileManager.default
    let requestedScript = homeDirectory.appending(
      path: ".local/bin/unsloth",
      directoryHint: .notDirectory
    )
    let script = requestedScript.resolvingSymlinksInPath().standardizedFileURL
    let python = absoluteShebangInterpreter(in: script)
    let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    return UnslothClientAdapter(
      pythonURL: python,
      scriptURL: fileManager.isExecutableFile(atPath: script.path) ? script : nil,
      environment: [
        "HOME": homeDirectory.path,
        "LANG": "en_US.UTF-8",
        "PATH": path,
        "TMPDIR": fileManager.temporaryDirectory.path,
      ]
    )
  }

  public func availability(
    for installation: ModelInstallation,
    context: ClientHandoffContext
  ) -> ClientAvailability {
    _ = context
    guard installation.state == .stored,
      [.gguf, .safetensors, .mlx].contains(installation.variant.format)
    else {
      return .unavailable(reason: "Unsloth Studio does not support this installation.")
    }
    guard pythonURL != nil, scriptURL != nil else {
      return .unavailable(reason: "Unsloth Studio was not found.")
    }
    return .available(summary: "Start local API-only Studio without tools or a public tunnel.")
  }

  public func makeHandoffPlan(
    for installation: ModelInstallation,
    context: ClientHandoffContext
  ) throws -> ClientHandoffPlan {
    guard installation.state == .stored,
      [.gguf, .safetensors, .mlx].contains(installation.variant.format)
    else {
      throw ClientAdapterError.unsupportedInstallation
    }
    guard let pythonURL, let scriptURL else { throw ClientAdapterError.toolNotInstalled }
    let python: ExecutableInspection
    let script: ExecutableInspection
    do {
      python = try inspector.inspect(pythonURL)
      script = try inspector.inspect(scriptURL)
    } catch {
      throw ClientAdapterError.invalidTool
    }
    guard let endpoint = URL(string: "http://127.0.0.1:\(port)") else {
      throw ClientAdapterError.invalidEndpoint
    }
    let invocation = RuntimeExecutableInvocation(
      executableURL: python.identity.requestedURL,
      arguments: [
        script.identity.canonicalURL.path,
        "studio", "run", "--model", installation.rootURL.path,
        "--host", "127.0.0.1", "--port", String(port), "--api-only",
        "--no-cloudflare", "--disable-tools",
      ],
      environment: environment,
      approvedIdentity: python.identity,
      protectedResourceIdentities: [script.identity]
    )
    return ClientHandoffPlan(
      adapterID: id,
      installationID: installation.id,
      modelReference: installation.rootURL.path,
      createdAt: context.now,
      expiresAt: context.now.addingTimeInterval(120),
      endpoint: endpoint,
      strategy: .executable(
        ClientExecutableHandoff(
          invocation: invocation,
          protectedResourceIdentities: [script.identity]
        )
      )
    )
  }

  private static func absoluteShebangInterpreter(in scriptURL: URL) -> URL? {
    guard let handle = try? FileHandle(forReadingFrom: scriptURL) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 512),
      let firstLine = String(data: data, encoding: .utf8)?.split(separator: "\n").first,
      firstLine.hasPrefix("#!/")
    else { return nil }
    let path = firstLine.dropFirst(2).split(separator: " ").first.map(String.init)
    guard let path, path.hasPrefix("/") else { return nil }
    return URL(filePath: path)
  }
}
