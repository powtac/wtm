import Darwin
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

@Test("Foundation launcher rejects an executable changed after approval")
func foundationLauncherRejectsChangedIdentity() throws {
  let root = URL(filePath: FileManager.default.currentDirectoryPath)
    .appending(path: ".build", directoryHint: .isDirectory).appending(
      path: "wtm-launcher-\(UUID().uuidString)", directoryHint: .isDirectory
    )
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(
    at: root.deletingLastPathComponent(), withIntermediateDirectories: true
  )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  chmod(root.path, 0o700)
  let executableURL = root.appending(path: "tool")
  try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
  chmod(executableURL.path, 0o700)
  let identity = try ExecutableInspector().inspect(executableURL).identity
  try Data("#!/bin/sh\nexit 1\n".utf8).write(to: executableURL)

  let invocation = RuntimeExecutableInvocation(
    executableURL: executableURL,
    arguments: [],
    approvedIdentity: identity
  )
  #expect(throws: RuntimeProcessLaunchError.approvedIdentityChanged) {
    _ = try FoundationProcessLauncher().launch(invocation) { _, _ in }
  }
}

@Test("Executable inspection rejects writable ancestor directories")
func executableInspectorRejectsUnsafeAncestor() throws {
  let root = FileManager.default.temporaryDirectory.appending(
    path: "wtm-unsafe-\(UUID().uuidString)", directoryHint: .isDirectory
  )
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
  chmod(root.path, 0o777)
  let executableURL = root.appending(path: "tool")
  try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
  chmod(executableURL.path, 0o700)

  #expect(throws: ExecutableInspectionError.unsafeAncestor) {
    _ = try ExecutableInspector().inspect(executableURL)
  }
}

@Test("Root-owned direct execution requires an entirely root-owned ancestor chain")
func rootOwnedBypassRequiresRootAncestors() {
  #expect(StagedInvocation.hasRootOwnedAncestors(of: URL(filePath: "/usr/bin/true")))
  let userControlledPath = URL(filePath: FileManager.default.currentDirectoryPath)
    .appending(path: ".build/tool")
  #expect(!StagedInvocation.hasRootOwnedAncestors(of: userControlledPath))
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
