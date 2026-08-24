import Foundation
import WTMDomain

public typealias RuntimeProcessOutputHandler = @Sendable (RuntimeLogStream, String) -> Void

public protocol RuntimeProcessHandle: Sendable {
  func processIdentifier() async -> Int32
  func isRunning() async -> Bool
  func terminate() async
  func waitForExit() async -> Int32
}

public protocol RuntimeProcessLaunching: Sendable {
  func launch(
    _ invocation: RuntimeExecutableInvocation,
    outputHandler: @escaping RuntimeProcessOutputHandler
  ) throws -> any RuntimeProcessHandle
}

public enum RuntimeProcessLaunchError: Error, Equatable, Sendable {
  case launchFailed(String)
}

public struct FoundationProcessLauncher: RuntimeProcessLaunching, Sendable {
  public init() {}

  public func launch(
    _ invocation: RuntimeExecutableInvocation,
    outputHandler: @escaping RuntimeProcessOutputHandler
  ) throws -> any RuntimeProcessHandle {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = invocation.executableURL
    process.arguments = invocation.arguments
    process.currentDirectoryURL = invocation.currentDirectoryURL
    process.environment = invocation.environment
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.standardInput = FileHandle.nullDevice

    standardOutput.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      outputHandler(.standardOutput, text)
    }
    standardError.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      outputHandler(.standardError, text)
    }

    do {
      try process.run()
    } catch {
      standardOutput.fileHandleForReading.readabilityHandler = nil
      standardError.fileHandleForReading.readabilityHandler = nil
      throw RuntimeProcessLaunchError.launchFailed(String(describing: error))
    }
    return FoundationRuntimeProcessHandle(
      process: process,
      standardOutput: standardOutput,
      standardError: standardError
    )
  }
}

private final class FoundationRuntimeProcessHandle: RuntimeProcessHandle, @unchecked Sendable {
  private let process: Process
  private let standardOutput: Pipe
  private let standardError: Pipe

  init(process: Process, standardOutput: Pipe, standardError: Pipe) {
    self.process = process
    self.standardOutput = standardOutput
    self.standardError = standardError
  }

  deinit {
    standardOutput.fileHandleForReading.readabilityHandler = nil
    standardError.fileHandleForReading.readabilityHandler = nil
  }

  func processIdentifier() async -> Int32 { process.processIdentifier }

  func isRunning() async -> Bool { process.isRunning }

  func terminate() async {
    guard process.isRunning else { return }
    process.terminate()
  }

  func waitForExit() async -> Int32 {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        self.process.waitUntilExit()
        self.standardOutput.fileHandleForReading.readabilityHandler = nil
        self.standardError.fileHandleForReading.readabilityHandler = nil
        continuation.resume(returning: self.process.terminationStatus)
      }
    }
  }
}
