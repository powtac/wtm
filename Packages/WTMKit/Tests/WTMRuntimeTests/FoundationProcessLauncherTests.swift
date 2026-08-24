import Foundation
import Testing
import WTMDomain

@testable import WTMRuntime

private final class LockedOutput: @unchecked Sendable {
  private let lock = NSLock()
  private var value = ""

  func append(_ text: String) {
    lock.lock()
    defer { lock.unlock() }
    value += text
  }

  func snapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

@Test("Foundation launcher passes hostile text as one argv value without a shell")
func foundationLauncherUsesDirectArguments() async throws {
  let executableURL = URL(filePath: "/usr/bin/printf")
  let identity = try ExecutableInspector().inspect(executableURL).identity
  let hostileValue = "model; echo SHOULD_NOT_RUN"
  let invocation = RuntimeExecutableInvocation(
    executableURL: executableURL,
    arguments: ["%s", hostileValue],
    environment: [:],
    approvedIdentity: identity
  )
  let output = LockedOutput()

  let handle = try FoundationProcessLauncher().launch(invocation) { _, text in
    output.append(text)
  }
  let status = await handle.waitForExit()
  try await Task.sleep(for: .milliseconds(10))

  #expect(status == 0)
  #expect(output.snapshot() == hostileValue)
}
