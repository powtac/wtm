import Foundation
import Observation

struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
  let major: Int
  let minor: Int
  let patch: Int
  let prerelease: [Identifier]

  enum Identifier: Comparable, Equatable, Sendable {
    case numeric(Int)
    case text(String)

    static func < (lhs: Identifier, rhs: Identifier) -> Bool {
      switch (lhs, rhs) {
      case let (.numeric(left), .numeric(right)):
        return left < right
      case (.numeric, .text):
        return true
      case (.text, .numeric):
        return false
      case let (.text(left), .text(right)):
        return left < right
      }
    }
  }

  static let zero = SemanticVersion(major: 0, minor: 0, patch: 0, prerelease: [])

  private init(major: Int, minor: Int, patch: Int, prerelease: [Identifier]) {
    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
  }

  init?(_ value: String) {
    let withoutPrefix = value.hasPrefix("v") ? String(value.dropFirst()) : value
    let buildParts = withoutPrefix.split(
      separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
    guard buildParts.count <= 2, !buildParts.contains(where: { $0.isEmpty }) else { return nil }

    let versionParts = buildParts[0].split(
      separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let core = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard core.count == 3,
      core.allSatisfy({ Self.isNumericComponent(String($0)) }),
      let major = Int(core[0]),
      let minor = Int(core[1]),
      let patch = Int(core[2])
    else { return nil }

    var prerelease: [Identifier] = []
    if versionParts.count == 2 {
      let identifiers = versionParts[1].split(separator: ".", omittingEmptySubsequences: false)
      guard !identifiers.isEmpty else { return nil }
      for identifier in identifiers {
        let value = String(identifier)
        guard value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
          return nil
        }
        if value.allSatisfy(\.isNumber) {
          guard value == "0" || !value.hasPrefix("0"), let numericValue = Int(value) else {
            return nil
          }
          prerelease.append(.numeric(numericValue))
        } else {
          prerelease.append(.text(value))
        }
      }
    }

    self.major = major
    self.minor = minor
    self.patch = patch
    self.prerelease = prerelease
  }

  var description: String {
    let core = "\(major).\(minor).\(patch)"
    guard !prerelease.isEmpty else { return core }
    return core + "-"
      + prerelease.map { identifier in
        switch identifier {
        case let .numeric(value): return String(value)
        case let .text(value): return value
        }
      }.joined(separator: ".")
  }

  static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
    let coreComparison = [lhs.major, lhs.minor, lhs.patch].lexicographicallyPrecedes(
      [rhs.major, rhs.minor, rhs.patch]
    )
    if lhs.major != rhs.major || lhs.minor != rhs.minor || lhs.patch != rhs.patch {
      return coreComparison
    }
    switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
    case (true, true): return false
    case (true, false): return false
    case (false, true): return true
    case (false, false):
      for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
        if left != right { return left < right }
      }
      return lhs.prerelease.count < rhs.prerelease.count
    }
  }

  private static func isNumericComponent(_ value: String) -> Bool {
    value == "0" || (!value.hasPrefix("0") && value.allSatisfy(\.isNumber))
  }
}

struct UpdateRelease: Equatable, Identifiable, Sendable {
  let version: SemanticVersion
  let title: String
  let htmlURL: URL
  let publishedAt: Date
  let releaseNotes: String
  let isPrerelease: Bool

  var id: String { version.description }
}

enum UpdateCheckState: Equatable, Sendable {
  case idle
  case checking
  case upToDate
  case updateAvailable(UpdateRelease)
  case noReleaseAvailable
  case offline
  case rateLimited(retryAfter: Date?)
  case failed

  var title: String {
    switch self {
    case .idle: return "Not checked"
    case .checking: return "Checking for updates…"
    case .upToDate: return "Up to Date"
    case .updateAvailable: return "Update Available"
    case .noReleaseAvailable: return "No Release Available"
    case .offline: return "Offline"
    case .rateLimited: return "Rate Limited"
    case .failed: return "Check Failed"
    }
  }
}

enum UpdateFetchError: Error, Equatable, Sendable {
  case httpStatus(Int)
  case rateLimited(retryAfter: Date?)
  case invalidMetadata
}

protocol UpdateReleaseFetching: Sendable {
  func fetchReleases() async throws -> [UpdateRelease]
}

struct GitHubReleaseFetcher: UpdateReleaseFetching {
  func fetchReleases() async throws -> [UpdateRelease] {
    var request = URLRequest(url: UpdateChecker.apiURL)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("WTM", forHTTPHeaderField: "User-Agent")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw UpdateFetchError.invalidMetadata
    }
    guard (200..<300).contains(response.statusCode) else {
      if response.statusCode == 403 || response.statusCode == 429 {
        throw UpdateFetchError.rateLimited(retryAfter: Self.retryAfter(from: response))
      }
      throw UpdateFetchError.httpStatus(response.statusCode)
    }

    let payloads: [GitHubReleasePayload]
    do {
      payloads = try JSONDecoder().decode([GitHubReleasePayload].self, from: data)
    } catch {
      throw UpdateFetchError.invalidMetadata
    }
    guard !payloads.isEmpty else { return [] }
    let releases = payloads.compactMap { $0.validatedRelease }
    guard !releases.isEmpty else { throw UpdateFetchError.invalidMetadata }
    return releases
  }

  private static func retryAfter(from response: HTTPURLResponse) -> Date? {
    guard let value = response.value(forHTTPHeaderField: "Retry-After"),
      let seconds = TimeInterval(value)
    else { return nil }
    return Date.now.addingTimeInterval(seconds)
  }
}

@MainActor
@Observable
final class UpdateChecker {
  nonisolated static let repositoryURL = makeURL("https://github.com/powtac/wtm")
  nonisolated static let releasesURL = makeURL("https://github.com/powtac/wtm/releases/latest")
  nonisolated static let apiURL = makeURL("https://api.github.com/repos/powtac/wtm/releases")
  nonisolated static let licenseURL = makeURL("https://github.com/powtac/wtm/blob/main/LICENSE")
  nonisolated static let automaticCheckInterval: TimeInterval = 7 * 24 * 60 * 60

  private nonisolated static let lastCheckKey = "updates.last-check"

  let currentVersion: SemanticVersion
  let releaseSourceURL = UpdateChecker.releasesURL
  private let fetcher: any UpdateReleaseFetching
  private let defaults: UserDefaults
  private(set) var state: UpdateCheckState = .idle
  private(set) var lastCheckedAt: Date?
  private var isRequestInFlight = false

  init(
    currentVersion: SemanticVersion = SemanticVersion(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    ) ?? .zero,
    fetcher: any UpdateReleaseFetching = GitHubReleaseFetcher(),
    defaults: UserDefaults = .standard
  ) {
    self.currentVersion = currentVersion
    self.fetcher = fetcher
    self.defaults = defaults
    lastCheckedAt = defaults.object(forKey: Self.lastCheckKey) as? Date
  }

  private nonisolated static func makeURL(_ string: String) -> URL {
    guard let url = URL(string: string) else { fatalError("Invalid WTM URL: \(string)") }
    return url
  }

  var currentVersionText: String { currentVersion.description }

  var shouldAutomaticallyCheck: Bool {
    guard let lastCheckedAt else { return true }
    return Date.now.timeIntervalSince(lastCheckedAt) >= Self.automaticCheckInterval
  }

  func checkAutomaticallyIfDue(now: Date = .now) async {
    guard !isRequestInFlight else { return }
    if let lastCheckedAt,
      now.timeIntervalSince(lastCheckedAt) < Self.automaticCheckInterval
    {
      return
    }
    await check(now: now)
  }

  func checkManually() {
    guard !isRequestInFlight else { return }
    Task { [weak self] in
      await self?.check(now: .now)
    }
  }

  func check(now: Date = .now) async {
    guard !isRequestInFlight else { return }
    isRequestInFlight = true
    state = .checking
    defer { isRequestInFlight = false }

    do {
      let releases = try await fetcher.fetchReleases()
      lastCheckedAt = now
      defaults.set(now, forKey: Self.lastCheckKey)
      let stableReleases = releases.filter { !$0.isPrerelease && $0.version.prerelease.isEmpty }
      guard let latest = stableReleases.max(by: { $0.version < $1.version }) else {
        state = .noReleaseAvailable
        return
      }
      state = latest.version > currentVersion ? .updateAvailable(latest) : .upToDate
    } catch let error as UpdateFetchError {
      lastCheckedAt = now
      defaults.set(now, forKey: Self.lastCheckKey)
      switch error {
      case .rateLimited(let retryAfter): state = .rateLimited(retryAfter: retryAfter)
      case .httpStatus, .invalidMetadata: state = .failed
      }
    } catch let error as URLError {
      lastCheckedAt = now
      defaults.set(now, forKey: Self.lastCheckKey)
      state =
        error.code == .notConnectedToInternet || error.code == .networkConnectionLost
        ? .offline : .failed
    } catch {
      lastCheckedAt = now
      defaults.set(now, forKey: Self.lastCheckKey)
      state = .failed
    }
  }
}

private struct GitHubReleasePayload: Decodable {
  let tagName: String?
  let name: String?
  let htmlURL: String?
  let publishedAt: String?
  let body: String?
  let prerelease: Bool?
  let draft: Bool?

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case name
    case htmlURL = "html_url"
    case publishedAt = "published_at"
    case body
    case prerelease
    case draft
  }

  var validatedRelease: UpdateRelease? {
    guard let tagName,
      let version = SemanticVersion(tagName),
      let htmlURL,
      let url = URL(string: htmlURL),
      UpdateChecker.isOfficialReleaseURL(url),
      let publishedAt,
      let date = ISO8601DateFormatter().date(from: publishedAt),
      draft != true
    else { return nil }
    let releaseTitle = (name?.isEmpty == false ? name : nil) ?? "WTM \(version)"
    return UpdateRelease(
      version: version,
      title: releaseTitle,
      htmlURL: url,
      publishedAt: date,
      releaseNotes: body ?? "No release notes provided.",
      isPrerelease: prerelease ?? false
    )
  }
}

extension UpdateChecker {
  nonisolated fileprivate static func isOfficialReleaseURL(_ url: URL) -> Bool {
    guard url.scheme == "https", url.host == "github.com" else { return false }
    return url.path.hasPrefix("/powtac/wtm/releases/")
  }
}
