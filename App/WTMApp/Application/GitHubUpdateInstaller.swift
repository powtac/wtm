import AppKit
import CryptoKit
import Security

@MainActor
protocol UpdateInstalling {
  func install(
    _ release: UpdateRelease,
    prepareForRelaunch: @MainActor () async -> Bool
  ) async throws -> Bool
}

struct GitHubUpdateInstaller: UpdateInstalling {
  private nonisolated static let bundleIdentifier = "de.powtac.whatthemodel"
  // Developer ID used for the official WTM distribution.
  private nonisolated static let signingRequirement =
    """
    anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists
    and certificate leaf[field.1.2.840.113635.100.6.1.13] exists
    and certificate leaf[subject.OU] = "E2J655BKXJ"
    """

  func install(
    _ release: UpdateRelease,
    prepareForRelaunch: @MainActor () async -> Bool
  ) async throws -> Bool {
    let installedApp = Bundle.main.bundleURL.resolvingSymlinksInPath()
    let staging = installedApp.deletingLastPathComponent()
      .appending(path: ".wtm-update-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var keepBackup = false
    defer {
      if !keepBackup {
        try? FileManager.default.removeItem(at: staging)
      }
    }
    let stagedApp = try await Self.prepare(release, installedApp: installedApp, staging: staging)
    guard await prepareForRelaunch() else { return false }

    // Keep the previous app in the staging directory until Launch Services accepts the new one.
    try Self.swap(stagedApp, installedApp)
    do {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      let runningApp = try await NSWorkspace.shared.openApplication(
        at: installedApp, configuration: configuration)
      guard runningApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
        throw InstallationError.relaunchFailed
      }
    } catch {
      keepBackup = true
      try Self.swap(stagedApp, installedApp)
      keepBackup = false
      throw error
    }
    return true
  }

  @concurrent
  static func prepare(_ release: UpdateRelease, installedApp: URL, staging: URL) async throws
    -> URL
  {
    let appRequirement = "\(signingRequirement) and identifier \"\(bundleIdentifier)\""
    try validateSignature(of: installedApp, requirement: appRequirement)
    guard
      let installedVersion = Bundle(url: installedApp)?
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      let currentVersion = SemanticVersion(installedVersion),
      release.version > currentVersion, !release.isPrerelease, release.version.prerelease.isEmpty
    else { throw InstallationError.invalidVersion }

    let version = release.version.description
    let assetDirectory = UpdateChecker.repositoryURL.appending(
      path: "releases/download/v\(version)")
    let imageName = "WTM-\(version)-arm64.dmg"
    let image = staging.appending(path: imageName)
    try await downloadImage(named: imageName, from: assetDirectory, version: version, to: image)
    try validateSignature(of: image, requirement: signingRequirement)

    let mounted = staging.appending(path: "mounted", directoryHint: .isDirectory)
    let stagedApp = staging.appending(path: "WTM.app", directoryHint: .isDirectory)
    let files = FileManager.default
    try files.createDirectory(at: mounted, withIntermediateDirectories: false)
    try run(
      "/usr/bin/hdiutil",
      ["attach", image.path, "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mounted.path])
    do {
      try files.copyItem(at: mounted.appending(path: "WTM.app"), to: stagedApp)
    } catch {
      try? run("/usr/bin/hdiutil", ["detach", mounted.path])
      throw error
    }
    try run("/usr/bin/hdiutil", ["detach", mounted.path])

    try validateSignature(
      of: stagedApp, requirement: appRequirement,
      flags: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)
    guard
      Bundle(url: stagedApp)?.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        as? String == version
    else { throw InstallationError.invalidVersion }
    try run("/usr/bin/syspolicy_check", ["distribution", stagedApp.path])
    return stagedApp
  }

  private nonisolated static func downloadImage(
    named imageName: String, from assetDirectory: URL, version: String, to image: URL
  ) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 120
    let session = URLSession(
      configuration: configuration, delegate: AssetRedirects(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }

    let checksumURL = assetDirectory.appending(path: "WTM-\(version).sha256")
    let (checksums, checksumResponse) = try await session.data(from: checksumURL)
    try validateResponse(checksumResponse)
    let entries = String(decoding: checksums, as: UTF8.self).split(whereSeparator: \.isNewline)
    let matchingEntries = entries.map { $0.split(whereSeparator: \.isWhitespace) }
      .filter { $0.count == 2 && $0[1] == imageName }
    guard matchingEntries.count == 1, let expectedDigest = matchingEntries.first?.first,
      expectedDigest.utf8.count == 64
    else { throw InstallationError.invalidChecksum }

    let (download, imageResponse) = try await session.download(
      from: assetDirectory.appending(path: imageName))
    defer { try? FileManager.default.removeItem(at: download) }
    try validateResponse(imageResponse)
    let data = try Data(contentsOf: download, options: .mappedIfSafe)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard digest == expectedDigest.lowercased() else { throw InstallationError.invalidChecksum }
    try FileManager.default.moveItem(at: download, to: image)
  }

  private nonisolated static func validateResponse(_ response: URLResponse) throws {
    guard let response = response as? HTTPURLResponse,
      response.statusCode == 200, AssetRedirects.isAllowed(response.url)
    else { throw InstallationError.invalidResponse }
  }

  private nonisolated static func validateSignature(
    of url: URL, requirement: String, flags: UInt32 = 0
  ) throws {
    var code: SecStaticCode?
    var expected: SecRequirement?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
      let code,
      SecRequirementCreateWithString(requirement as CFString, [], &expected) == errSecSuccess,
      let expected,
      SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: flags), expected) == errSecSuccess
    else { throw InstallationError.invalidSignature }
  }

  private nonisolated static func run(_ executable: String, _ arguments: [String]) throws {
    let command = Process()
    command.executableURL = URL(filePath: executable)
    command.arguments = arguments
    command.standardInput = FileHandle.nullDevice
    command.standardOutput = FileHandle.nullDevice
    command.standardError = FileHandle.nullDevice
    try command.run()
    command.waitUntilExit()
    guard command.terminationReason == .exit, command.terminationStatus == 0 else {
      throw InstallationError.toolFailed(executable, command.terminationStatus)
    }
  }

  nonisolated static func swap(_ first: URL, _ second: URL) throws {
    guard renamex_np(first.path, second.path, UInt32(RENAME_SWAP)) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  private enum InstallationError: Error {
    case invalidResponse, invalidChecksum, invalidSignature, invalidVersion, relaunchFailed
    case toolFailed(String, Int32)
  }
}

private final class AssetRedirects: NSObject, URLSessionTaskDelegate {
  static func isAllowed(_ url: URL?) -> Bool {
    guard let url, url.scheme == "https" else { return false }
    return url.host == "github.com" || url.host == "release-assets.githubusercontent.com"
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(Self.isAllowed(request.url) ? request : nil)
  }
}
