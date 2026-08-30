import Darwin
import Foundation
import WTMDomain
import WTMSecurity

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
  case approvedIdentityChanged
  case protectedResourceNotReferenced
  case protectedPathIdentityChanged
  case stagingFailed(String)
}

public struct FoundationProcessLauncher: RuntimeProcessLaunching, Sendable {
  public init() {}

  public func launch(
    _ invocation: RuntimeExecutableInvocation,
    outputHandler: @escaping RuntimeProcessOutputHandler
  ) throws -> any RuntimeProcessHandle {
    let staged = try StagedInvocation(invocation)
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = staged.executableURL
    process.arguments = staged.arguments
    process.currentDirectoryURL = invocation.currentDirectoryURL
    process.environment = invocation.environment
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.standardInput = FileHandle.nullDevice

    standardOutput.fileHandleForReading.readabilityHandler = { handle in
      let data = (try? handle.read(upToCount: 64 * 1_024)) ?? Data()
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      outputHandler(.standardOutput, text)
    }
    standardError.fileHandleForReading.readabilityHandler = { handle in
      let data = (try? handle.read(upToCount: 64 * 1_024)) ?? Data()
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      outputHandler(.standardError, text)
    }

    do {
      try process.run()
    } catch {
      standardOutput.fileHandleForReading.readabilityHandler = nil
      standardError.fileHandleForReading.readabilityHandler = nil
      staged.remove()
      throw RuntimeProcessLaunchError.launchFailed(String(describing: error))
    }
    return FoundationRuntimeProcessHandle(
      process: process,
      standardOutput: standardOutput,
      standardError: standardError,
      stagedInvocation: staged
    )
  }
}

private final class FoundationRuntimeProcessHandle: RuntimeProcessHandle, @unchecked Sendable {
  private let process: Process
  private let standardOutput: Pipe
  private let standardError: Pipe
  private let stagedInvocation: StagedInvocation

  init(
    process: Process,
    standardOutput: Pipe,
    standardError: Pipe,
    stagedInvocation: StagedInvocation
  ) {
    self.process = process
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.stagedInvocation = stagedInvocation
  }

  deinit {
    standardOutput.fileHandleForReading.readabilityHandler = nil
    standardError.fileHandleForReading.readabilityHandler = nil
    stagedInvocation.remove()
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
        self.stagedInvocation.remove()
        continuation.resume(returning: self.process.terminationStatus)
      }
    }
  }
}

final class StagedInvocation: @unchecked Sendable {
  let executableURL: URL
  let arguments: [String]
  private let directoryURL: URL
  private let lock = NSLock()
  private var removed = false

  init(_ invocation: RuntimeExecutableInvocation) throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appending(path: "wtm-exec-\(UUID().uuidString)", directoryHint: .isDirectory)
    do {
      for identity in invocation.protectedPathIdentities {
        do {
          try FileMetadataReader().validate(identity)
        } catch {
          throw RuntimeProcessLaunchError.protectedPathIdentityChanged
        }
      }
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      executableURL = try Self.stageOrUseRootOwned(
        invocation.approvedIdentity,
        in: directoryURL,
        name: "executable",
        mode: 0o500
      )
      var rewritten = invocation.arguments
      for (index, identity) in invocation.protectedResourceIdentities.enumerated() {
        let candidates = Set([identity.requestedURL.path, identity.canonicalURL.path])
        let argumentIndices = rewritten.indices.filter { candidates.contains(rewritten[$0]) }
        guard !argumentIndices.isEmpty else {
          throw RuntimeProcessLaunchError.protectedResourceNotReferenced
        }
        let suffix = identity.canonicalURL.pathExtension
        let name = suffix.isEmpty ? "resource-\(index)" : "resource-\(index).\(suffix)"
        let stagedURL = try Self.stageOrUseRootOwned(
          identity,
          in: directoryURL,
          name: name,
          mode: 0o400
        )
        for argumentIndex in argumentIndices {
          rewritten[argumentIndex] = stagedURL.path
        }
      }
      for (index, identity) in invocation.protectedPathIdentities.enumerated() {
        guard identity.mode & UInt32(S_IFMT) == UInt32(S_IFREG) else { continue }
        let candidates = Set([identity.requestedURL.path, identity.canonicalURL.path])
        let argumentIndices = rewritten.indices.filter { candidates.contains(rewritten[$0]) }
        guard !argumentIndices.isEmpty else {
          throw RuntimeProcessLaunchError.protectedResourceNotReferenced
        }
        let suffix = identity.canonicalURL.pathExtension
        let name = suffix.isEmpty ? "path-\(index)" : "path-\(index).\(suffix)"
        let stagedURL = try Self.copyVerified(
          identity,
          to: directoryURL.appending(path: name, directoryHint: .notDirectory),
          mode: 0o400
        )
        for argumentIndex in argumentIndices {
          rewritten[argumentIndex] = stagedURL.path
        }
      }
      arguments = rewritten
    } catch {
      try? FileManager.default.removeItem(at: directoryURL)
      throw error
    }
  }

  func remove() {
    lock.lock()
    defer { lock.unlock() }
    guard !removed else { return }
    removed = true
    try? FileManager.default.removeItem(at: directoryURL)
  }

  private static func copyVerified(
    _ identity: ExecutableIdentity,
    to destination: URL,
    mode: mode_t
  ) throws -> URL {
    let sourceFD = open(identity.canonicalURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard sourceFD >= 0 else { throw RuntimeProcessLaunchError.approvedIdentityChanged }
    defer { close(sourceFD) }
    var information = stat()
    guard fstat(sourceFD, &information) == 0,
      UInt64(information.st_dev) == identity.deviceID,
      UInt64(information.st_ino) == identity.fileID,
      UInt32(information.st_uid) == identity.ownerUserID,
      UInt32(information.st_gid) == identity.ownerGroupID,
      UInt32(information.st_mode) == identity.mode,
      Int64(information.st_size) == identity.byteCount,
      Int64(information.st_mtimespec.tv_sec) == identity.modificationSeconds,
      Int64(information.st_mtimespec.tv_nsec) == identity.modificationNanoseconds
    else { throw RuntimeProcessLaunchError.approvedIdentityChanged }

    let targetFD = open(
      destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
    guard targetFD >= 0 else {
      throw RuntimeProcessLaunchError.stagingFailed("Could not create private staged file.")
    }
    defer { close(targetFD) }
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      let count = read(sourceFD, &buffer, buffer.count)
      if count == 0 { break }
      guard count > 0 else {
        throw RuntimeProcessLaunchError.stagingFailed("Could not read approved file.")
      }
      var offset = 0
      while offset < count {
        let written = buffer.withUnsafeBytes { bytes in
          guard let baseAddress = bytes.baseAddress else { return -1 }
          return write(targetFD, baseAddress.advanced(by: offset), count - offset)
        }
        guard written > 0 else {
          throw RuntimeProcessLaunchError.stagingFailed("Could not write staged file.")
        }
        offset += written
      }
    }
    guard fsync(targetFD) == 0 else {
      throw RuntimeProcessLaunchError.stagingFailed("Could not sync staged file.")
    }
    return destination
  }

  private static func copyVerified(
    _ identity: RuntimePathIdentity,
    to destination: URL,
    mode: mode_t
  ) throws -> URL {
    let sourceFD = open(identity.canonicalURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard sourceFD >= 0 else { throw RuntimeProcessLaunchError.protectedPathIdentityChanged }
    defer { close(sourceFD) }
    var information = stat()
    guard fstat(sourceFD, &information) == 0,
      UInt64(information.st_dev) == identity.deviceID,
      UInt64(information.st_ino) == identity.fileID,
      UInt32(information.st_mode) == identity.mode,
      Int64(information.st_size) == identity.byteCount,
      Int64(information.st_mtimespec.tv_sec) == identity.modificationSeconds,
      Int64(information.st_mtimespec.tv_nsec) == identity.modificationNanoseconds
    else { throw RuntimeProcessLaunchError.protectedPathIdentityChanged }

    let targetFD = open(
      destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
    guard targetFD >= 0 else {
      throw RuntimeProcessLaunchError.stagingFailed("Could not create private staged file.")
    }
    defer { close(targetFD) }
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while true {
      let count = read(sourceFD, &buffer, buffer.count)
      if count == 0 { break }
      guard count > 0 else {
        throw RuntimeProcessLaunchError.stagingFailed("Could not read protected file.")
      }
      var offset = 0
      while offset < count {
        let written = buffer.withUnsafeBytes { bytes in
          guard let baseAddress = bytes.baseAddress else { return -1 }
          return write(targetFD, baseAddress.advanced(by: offset), count - offset)
        }
        guard written > 0 else {
          throw RuntimeProcessLaunchError.stagingFailed("Could not write staged file.")
        }
        offset += written
      }
    }
    guard fsync(targetFD) == 0 else {
      throw RuntimeProcessLaunchError.stagingFailed("Could not sync staged file.")
    }
    return destination
  }

  private static func stageOrUseRootOwned(
    _ identity: ExecutableIdentity,
    in directory: URL,
    name: String,
    mode: mode_t
  ) throws -> URL {
    // macOS can reject private copies of Apple platform binaries. A root-owned,
    // non-writable object under validated ancestors is already outside user control.
    if identity.ownerUserID == 0, hasRootOwnedAncestors(of: identity.canonicalURL) {
      try verify(identity)
      return identity.canonicalURL
    }
    return try copyVerified(
      identity,
      to: directory.appending(path: name, directoryHint: .notDirectory),
      mode: mode
    )
  }

  static func hasRootOwnedAncestors(of url: URL) -> Bool {
    var directory = url.deletingLastPathComponent().standardizedFileURL
    while true {
      var information = stat()
      guard lstat(directory.path, &information) == 0,
        (information.st_mode & S_IFMT) == S_IFDIR,
        information.st_uid == 0,
        (information.st_mode & (S_IWGRP | S_IWOTH)) == 0
      else { return false }
      let parent = directory.deletingLastPathComponent().standardizedFileURL
      if parent == directory { return true }
      directory = parent
    }
  }

  private static func verify(_ identity: ExecutableIdentity) throws {
    let descriptor = open(identity.canonicalURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw RuntimeProcessLaunchError.approvedIdentityChanged }
    defer { close(descriptor) }
    var information = stat()
    guard fstat(descriptor, &information) == 0,
      UInt64(information.st_dev) == identity.deviceID,
      UInt64(information.st_ino) == identity.fileID,
      UInt32(information.st_uid) == identity.ownerUserID,
      UInt32(information.st_gid) == identity.ownerGroupID,
      UInt32(information.st_mode) == identity.mode,
      Int64(information.st_size) == identity.byteCount,
      Int64(information.st_mtimespec.tv_sec) == identity.modificationSeconds,
      Int64(information.st_mtimespec.tv_nsec) == identity.modificationNanoseconds
    else { throw RuntimeProcessLaunchError.approvedIdentityChanged }
  }
}
