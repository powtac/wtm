import Foundation
import WTMDomain

public enum RuntimeLogStream: String, Codable, CaseIterable, Sendable {
  case standardOutput
  case standardError
  case system
}

public struct RuntimeLogEntry: Identifiable, Hashable, Codable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let stream: RuntimeLogStream
  public let message: String

  public init(
    id: UUID = UUID(),
    timestamp: Date = .now,
    stream: RuntimeLogStream,
    message: String
  ) {
    self.id = id
    self.timestamp = timestamp
    self.stream = stream
    self.message = message
  }
}

public struct RuntimeLogRedactor: Sendable {
  private let sensitiveValues: [String]

  public init(sensitiveValues: [String] = []) {
    self.sensitiveValues = sensitiveValues.filter { $0.utf8.count >= 4 }
  }

  public init(
    invocation: RuntimeExecutableInvocation,
    additionalSensitiveValues: [String] = []
  ) {
    var invocationPaths = [
      invocation.executableURL.path,
      invocation.approvedIdentity.requestedURL.path,
      invocation.approvedIdentity.canonicalURL.path,
    ]
    if let currentDirectoryPath = invocation.currentDirectoryURL?.path {
      invocationPaths.append(currentDirectoryPath)
    }
    for identity in invocation.protectedResourceIdentities {
      invocationPaths.append(identity.requestedURL.path)
      invocationPaths.append(identity.canonicalURL.path)
    }
    let argumentPaths = invocation.arguments.filter { $0.hasPrefix("/") }
    self.init(
      sensitiveValues: Array(
        Set(
          invocationPaths + argumentPaths + invocation.environment.values
            + additionalSensitiveValues)
      )
    )
  }

  public func redact(_ input: String) -> String {
    var output = input
    for value in sensitiveValues {
      output = output.replacingOccurrences(of: value, with: "<redacted>")
    }
    for pattern in Self.credentialPatterns {
      output = output.replacingOccurrences(
        of: pattern,
        with: "$1<redacted>",
        options: [.regularExpression, .caseInsensitive]
      )
    }
    return output
  }

  private static let credentialPatterns = [
    #"(Bearer\s+)[^\s\"']+"#,
    #"((?:api[_-]?key|access[_-]?token|auth[_-]?token|token|password)\s*[:=]\s*[\"']?)[^\s,\"']+"#,
  ]
}

public final class RuntimeLogBuffer: @unchecked Sendable {
  private let maximumEntries: Int
  private let maximumUTF8ByteCount: Int
  private let redactor: RuntimeLogRedactor
  private let lock = NSLock()
  private var entries: [RuntimeLogEntry] = []
  private var utf8ByteCount = 0

  public init(
    maximumEntries: Int = 256,
    maximumUTF8ByteCount: Int = 64 * 1_024,
    redactor: RuntimeLogRedactor = RuntimeLogRedactor()
  ) {
    self.maximumEntries = max(maximumEntries, 1)
    self.maximumUTF8ByteCount = max(maximumUTF8ByteCount, 1_024)
    self.redactor = redactor
  }

  public func append(
    _ text: String,
    stream: RuntimeLogStream,
    timestamp: Date = .now
  ) {
    lock.lock()
    defer { lock.unlock() }
    let redacted = redactor.redact(text)
    let lines = redacted.split(
      omittingEmptySubsequences: true, whereSeparator: \Character.isNewline)
    for line in lines {
      let message = String(line)
      let entry = RuntimeLogEntry(timestamp: timestamp, stream: stream, message: message)
      entries.append(entry)
      utf8ByteCount += message.utf8.count
    }
    trimIfNeeded()
  }

  public func snapshot() -> [RuntimeLogEntry] {
    lock.lock()
    defer { lock.unlock() }
    return entries
  }

  private func trimIfNeeded() {
    while entries.count > maximumEntries || utf8ByteCount > maximumUTF8ByteCount {
      guard !entries.isEmpty else { break }
      utf8ByteCount -= entries.removeFirst().message.utf8.count
    }
  }
}
