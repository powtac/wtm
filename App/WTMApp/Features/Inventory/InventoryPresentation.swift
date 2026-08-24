import Foundation
import WTMDomain
import WTMInventory

extension ProviderID {
  var localizedName: String {
    switch self {
    case .ollama: String(localized: "provider.ollama")
    case .huggingFace: String(localized: "provider.hugging-face")
    case .manual: String(localized: "provider.manual")
    default: rawValue
    }
  }
}

extension ModelFormat {
  var localizedName: String {
    switch self {
    case .gguf: String(localized: "format.gguf")
    case .safetensors: String(localized: "format.safetensors")
    case .mlx: String(localized: "format.mlx")
    case .ollama: String(localized: "format.ollama")
    case .unknown: String(localized: "format.unknown")
    }
  }
}

extension InstallationState {
  var localizedName: String {
    switch self {
    case .stored: String(localized: "installation-state.stored")
    case .incomplete: String(localized: "installation-state.incomplete")
    case .issue: String(localized: "installation-state.issue")
    case .offline: String(localized: "installation-state.offline")
    }
  }
}

extension SourceAccessState {
  var localizedName: String {
    switch self {
    case .notSetUp: String(localized: "source.access.not-set-up")
    case .allowed: String(localized: "source.access.allowed")
    case .limited: String(localized: "source.access.limited")
    case .denied: String(localized: "source.access.denied")
    case .offline: String(localized: "source.access.offline")
    case .stale: String(localized: "source.access.stale")
    }
  }
}

extension TimestampKind {
  var localizedName: String {
    switch self {
    case .providerDownload: String(localized: "timestamp.provider-download")
    case .fileCreation: String(localized: "timestamp.file-creation")
    case .fileModification: String(localized: "timestamp.file-modification")
    case .observedThisScan: String(localized: "timestamp.observed-this-scan")
    }
  }
}

extension ModelInstallation {
  var inventorySortName: String { identity.displayName }
  var inventorySortProvider: String { providerID.localizedName }
  var inventorySortFormat: String { variant.format.localizedName }
  var inventorySortState: String { state.localizedName }
  var inventorySortSize: Int64 { allocatedByteCount }
  var inventorySortAge: TimeInterval {
    earliestChangeTimestamp.map { -$0.value.timeIntervalSinceReferenceDate }
      ?? .greatestFiniteMagnitude
  }
  var inventorySortPath: String { rootURL.path }
}

enum StorageDisplayMode: String, CaseIterable {
  case absolute
  case share
}

struct InventoryTableRow: Identifiable {
  let installation: ModelInstallation
  let displayedByteCount: Int64

  var id: ModelInstallation.ID { installation.id }
  var sortName: String { installation.inventorySortName }
  var sortProvider: String { installation.inventorySortProvider }
  var sortFormat: String { installation.inventorySortFormat }
  var sortState: String { installation.inventorySortState }
  var sortSize: Int64 { displayedByteCount }
  var sortAge: TimeInterval { installation.inventorySortAge }
  var sortPath: String { installation.inventorySortPath }
}

func inventoryTableRows(
  installations: [ModelInstallation],
  mode: StorageDisplayMode,
  breakdown: InventoryStorageBreakdown
) -> [InventoryTableRow] {
  installations.map { installation in
    InventoryTableRow(
      installation: installation,
      displayedByteCount: mode == .absolute
        ? installation.allocatedByteCount
        : breakdown.exclusiveByteCount(for: installation.id)
    )
  }
}

func percentageText(_ byteCount: Int64, of totalByteCount: Int64) -> String {
  guard totalByteCount > 0 else { return 0.formatted(.percent) }
  return (Double(byteCount) / Double(totalByteCount)).formatted(
    .percent.precision(.fractionLength(0))
  )
}

func validatedModelCardURL(_ link: ModelCardLink?) -> URL? {
  guard let url = link?.url, url.scheme?.lowercased() == "https", url.host() != nil else {
    return nil
  }
  return url
}

func wholeByteCount(_ value: Int64, locale: Locale = .current) -> String {
  let bytes = max(0, value)
  let scaled: (value: Double, unit: UnitInformationStorage)
  switch bytes {
  case 0..<1_000:
    scaled = (Double(bytes), .bytes)
  case 1_000..<1_000_000:
    scaled = (Double(bytes) / 1_000, .kilobytes)
  case 1_000_000..<1_000_000_000:
    scaled = (Double(bytes) / 1_000_000, .megabytes)
  case 1_000_000_000..<1_000_000_000_000:
    scaled = (Double(bytes) / 1_000_000_000, .gigabytes)
  case 1_000_000_000_000..<1_000_000_000_000_000:
    scaled = (Double(bytes) / 1_000_000_000_000, .terabytes)
  default:
    scaled = (Double(bytes) / 1_000_000_000_000_000, .petabytes)
  }

  let formatter = MeasurementFormatter()
  formatter.locale = locale
  formatter.unitOptions = .providedUnit
  formatter.unitStyle = .medium
  formatter.numberFormatter.minimumFractionDigits = 0
  formatter.numberFormatter.maximumFractionDigits = 0
  formatter.numberFormatter.roundingMode = .halfUp
  return formatter.string(from: Measurement(value: scaled.value, unit: scaled.unit))
}

func installationAgeText(
  _ installation: ModelInstallation,
  relativeTo referenceDate: Date = .now,
  locale: Locale = .current
) -> String {
  guard let timestamp = installation.earliestChangeTimestamp else {
    return String(localized: "age.unknown", locale: locale)
  }

  let elapsedSeconds = max(0, referenceDate.timeIntervalSince(timestamp.value))
  let unit: String.LocalizationValue
  let count: Int
  switch elapsedSeconds {
  case ..<3_600:
    count = Int(elapsedSeconds / 60)
    unit = count == 1 ? "age.minute" : "age.minutes"
  case ..<86_400:
    count = Int(elapsedSeconds / 3_600)
    unit = count == 1 ? "age.hour" : "age.hours"
  case ..<(365 * 86_400):
    count = Int(elapsedSeconds / 86_400)
    unit = count == 1 ? "age.day" : "age.days"
  default:
    count = Int(elapsedSeconds / (365 * 86_400))
    unit = count == 1 ? "age.year" : "age.years"
  }
  return "\(count.formatted(.number.locale(locale))) \(String(localized: unit, locale: locale))"
}

func artifactSectionTitle(count: Int) -> String {
  let noun = String(localized: count == 1 ? "detail.artifact" : "detail.artifacts")
  return "\(count) \(noun)"
}

func artifactsSortedByName(_ artifacts: [Artifact]) -> [Artifact] {
  artifacts.sorted { left, right in
    let nameComparison = left.url.lastPathComponent.localizedStandardCompare(
      right.url.lastPathComponent
    )
    if nameComparison != .orderedSame {
      return nameComparison == .orderedAscending
    }
    return left.url.path.localizedStandardCompare(right.url.path) == .orderedAscending
  }
}
