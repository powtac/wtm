import AppKit
import SwiftUI

struct UpdateStatusView: View {
  let checker: UpdateChecker
  var showsCheckButton = true
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 6 : 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(checker.state.title)
          .font(.headline)
        Spacer()
        if showsCheckButton {
          Button("Check for Updates…") {
            checker.checkManually()
          }
          .accessibilityIdentifier("check-for-updates-button")
        }
      }

      Text(statusMessage)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if let release = availableRelease {
        VStack(alignment: .leading, spacing: 5) {
          Text("Version \(release.version.description)")
          Text("Published \(release.publishedAt, format: .dateTime.year().month().day())")
          if !compact {
            Text("Release notes")
              .font(.subheadline.weight(.semibold))
            Text(release.releaseNotes)
              .font(.callout)
              .textSelection(.enabled)
              .lineLimit(8)
          }
          HStack {
            Link("View Release on GitHub", destination: release.htmlURL)
            Link("Download Latest Release", destination: release.htmlURL)
              .accessibilityIdentifier("download-latest-release-link")
          }
        }
      } else if !compact {
        HStack {
          Link("View Releases on GitHub", destination: checker.releaseSourceURL)
          Link("Download Latest Release", destination: checker.releaseSourceURL)
            .accessibilityIdentifier("download-latest-release-link")
        }
      }

      if let lastCheckedAt = checker.lastCheckedAt {
        Text(
          "Last checked \(lastCheckedAt, format: .dateTime.year().month().day().hour().minute())"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      if !compact {
        Text("Source: \(checker.releaseSourceURL.absoluteString)")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("update-status")
  }

  private var availableRelease: UpdateRelease? {
    guard case let .updateAvailable(release) = checker.state else { return nil }
    return release
  }

  private var statusMessage: String {
    switch checker.state {
    case .idle:
      return "WTM has not checked the official GitHub Releases yet."
    case .checking:
      return "Checking the official GitHub Releases. No inventory or device data is sent."
    case .upToDate:
      return "What The Model \(checker.currentVersionText) is the latest stable release."
    case let .updateAvailable(release):
      return
        "What The Model \(checker.currentVersionText) can be updated to \(release.version.description)."
    case .noReleaseAvailable:
      return "The official repository has no stable release available yet."
    case .offline:
      return "GitHub could not be reached. Check your connection and try again."
    case let .rateLimited(retryAfter):
      if let retryAfter {
        let retryTime = retryAfter.formatted(date: .omitted, time: .shortened)
        return "GitHub temporarily rate-limited this check. Try again after \(retryTime)."
      }
      return "GitHub temporarily rate-limited this check. Try again later."
    case .failed:
      return "The release metadata was unavailable or invalid. Try again later."
    }
  }
}

struct AboutView: View {
  let checker: UpdateChecker

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 14) {
        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
          .resizable()
          .frame(width: 72, height: 72)
          .accessibilityLabel("What The Model application icon")
        VStack(alignment: .leading, spacing: 4) {
          Text("app.name")
            .font(.title2.weight(.semibold))
          Text("app.subtitle")
            .foregroundStyle(.secondary)
          Text("Version \(checker.currentVersionText) (Build \(buildNumber))")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      UpdateStatusView(checker: checker)

      HStack {
        Link("Repository on GitHub", destination: UpdateChecker.repositoryURL)
        Link("Apache License 2.0", destination: UpdateChecker.licenseURL)
      }
    }
    .padding(24)
    .frame(width: 560)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var buildNumber: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
  }
}
