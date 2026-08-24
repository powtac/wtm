import Foundation
import WTMDomain

struct SourceSettingsSnapshot: Sendable {
  let revision: UInt64
  let sources: [ScanSource]
  let hasCompletedOnboarding: Bool
  let scanOnLaunch: Bool
  let oldModelThresholdDays: Int

  init(
    revision: UInt64,
    sources: [ScanSource],
    hasCompletedOnboarding: Bool,
    scanOnLaunch: Bool,
    oldModelThresholdDays: Int = 90
  ) {
    self.revision = revision
    self.sources = sources
    self.hasCompletedOnboarding = hasCompletedOnboarding
    self.scanOnLaunch = scanOnLaunch
    self.oldModelThresholdDays = min(max(oldModelThresholdDays, 1), 3_650)
  }
}

protocol SourceSettingsStoring: Sendable {
  func load() async throws -> SourceSettingsSnapshot?
  func save(_ snapshot: SourceSettingsSnapshot) async throws
  func makeManualSource(for url: URL) async -> ScanSource
  func replace(_ source: ScanSource, with url: URL) async -> ScanSource
}

actor JSONSourceSettingsStore: SourceSettingsStoring {
  private struct Payload: Codable {
    static let currentVersion = 1

    let version: Int
    let revision: UInt64
    let sources: [StoredSource]
    let hasCompletedOnboarding: Bool
    let scanOnLaunch: Bool
    let oldModelThresholdDays: Int?
  }

  private struct StoredSource: Codable {
    let source: ScanSource
    let bookmarkData: Data?
  }

  private let settingsURL: URL
  private var highestSavedRevision: UInt64 = 0

  init(settingsURL: URL) {
    self.settingsURL = settingsURL
  }

  func load() throws -> SourceSettingsSnapshot? {
    guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
    let data = try Data(contentsOf: settingsURL, options: [.mappedIfSafe])
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    guard payload.version == Payload.currentVersion else { return nil }

    highestSavedRevision = payload.revision
    return SourceSettingsSnapshot(
      revision: payload.revision,
      sources: payload.sources.map(resolve),
      hasCompletedOnboarding: payload.hasCompletedOnboarding,
      scanOnLaunch: payload.scanOnLaunch,
      oldModelThresholdDays: payload.oldModelThresholdDays ?? 90
    )
  }

  func save(_ snapshot: SourceSettingsSnapshot) throws {
    guard snapshot.revision >= highestSavedRevision else { return }
    let records = snapshot.sources.map { source in
      StoredSource(source: source, bookmarkData: try? bookmarkData(for: source.rootURL))
    }
    let payload = Payload(
      version: Payload.currentVersion,
      revision: snapshot.revision,
      sources: records,
      hasCompletedOnboarding: snapshot.hasCompletedOnboarding,
      scanOnLaunch: snapshot.scanOnLaunch,
      oldModelThresholdDays: snapshot.oldModelThresholdDays
    )
    let data = try JSONEncoder().encode(payload)
    try FileManager.default.createDirectory(
      at: settingsURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: settingsURL, options: [.atomic])
    highestSavedRevision = snapshot.revision
  }

  func makeManualSource(for url: URL) -> ScanSource {
    let standardizedURL = url.standardizedFileURL
    return ScanSource(
      id: "manual:\(UUID().uuidString.lowercased())",
      displayName: standardizedURL.lastPathComponent,
      providerID: .manual,
      rootURL: standardizedURL,
      volumeIdentity: volumeIdentity(for: standardizedURL),
      accessState: .allowed,
      isEnabled: true
    )
  }

  func replace(_ source: ScanSource, with url: URL) -> ScanSource {
    let standardizedURL = url.standardizedFileURL
    return ScanSource(
      id: source.id,
      displayName: source.displayName,
      providerID: source.providerID,
      rootURL: standardizedURL,
      volumeIdentity: volumeIdentity(for: standardizedURL),
      accessState: .allowed,
      isEnabled: true
    )
  }

  private func resolve(_ record: StoredSource) -> ScanSource {
    guard let bookmarkData = record.bookmarkData else { return record.source }
    var isStale = false
    guard
      let resolvedURL = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    else {
      return record.source
    }

    let source = record.source
    return ScanSource(
      id: source.id,
      displayName: source.displayName,
      providerID: source.providerID,
      rootURL: resolvedURL.standardizedFileURL,
      volumeIdentity: source.volumeIdentity,
      accessState: source.accessState,
      isEnabled: source.isEnabled
    )
  }

  private func bookmarkData(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: [
        .volumeIdentifierKey,
        .volumeUUIDStringKey,
        .volumeURLKey,
      ],
      relativeTo: nil
    )
  }

  private func volumeIdentity(for url: URL) -> VolumeIdentity? {
    let sourcePath = url.standardizedFileURL.path
    guard
      let volumeURL = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeIdentifierKey, .volumeUUIDStringKey],
        options: [.skipHiddenVolumes]
      )?.filter({ candidate in
        let volumePath = candidate.standardizedFileURL.path
        let volumePrefix = volumePath.hasSuffix("/") ? volumePath : volumePath + "/"
        return sourcePath == volumePath || sourcePath.hasPrefix(volumePrefix)
      }).max(by: { $0.path.count < $1.path.count }),
      let values = try? volumeURL.resourceValues(
        forKeys: [.volumeIdentifierKey, .volumeUUIDStringKey]
      ),
      let identifier = values.volumeIdentifier
    else {
      return nil
    }

    let volumePath = volumeURL.standardizedFileURL.path
    let relativePath =
      sourcePath.hasPrefix(volumePath)
      ? String(sourcePath.dropFirst(volumePath.count)).trimmingCharacters(
        in: CharacterSet(charactersIn: "/"))
      : sourcePath
    return VolumeIdentity(
      identifier: values.volumeUUIDString ?? String(describing: identifier),
      relativePath: relativePath
    )
  }
}
