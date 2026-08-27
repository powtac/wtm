import AppKit
import Foundation
import WTMDomain
import WTMInventory

extension ProviderID {
  var localizedName: String {
    switch self {
    case .ollama: String(localized: "provider.ollama")
    case .huggingFace: String(localized: "provider.hugging-face")
    case .mlx: String(localized: "provider.mlx")
    case .manual: String(localized: "provider.manual")
    default: rawValue
    }
  }

  var inventorySourceTypeName: String {
    self == .manual ? String(localized: "source.type.manual-folder") : localizedName
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

extension InventoryIssue {
  var localizedSummary: String {
    switch code {
    case "HF_CACHE_ENUMERATION_FAILED", "HF_REPOSITORY_INVALID", "HF_DOWNLOAD_INCOMPLETE":
      String(localized: "issue.hugging-face")
    case "OLLAMA_ENUMERATION_FAILED", "OLLAMA_MANIFEST_INVALID", "OLLAMA_MANIFEST_PATH_INVALID",
      "OLLAMA_BLOB_MISSING", "OLLAMA_BLOB_REFERENCE_INVALID":
      String(localized: "issue.ollama")
    case "MANUAL_ENUMERATION_FAILED":
      String(localized: "issue.manual")
    case "MLX_ENUMERATION_FAILED", "MLX_CONFIGURATION_INVALID", "MLX_STRUCTURE_UNCONFIRMED",
      "MLX_WEIGHTS_INCOMPLETE", "MLX_TOKENIZER_MISSING":
      String(localized: "issue.mlx")
    case "SOURCE_OFFLINE":
      String(localized: "issue.source-offline")
    case "SOURCE_NOT_READABLE", "SOURCE_ACCESS_STALE", "SOURCE_NOT_ALLOWED":
      String(localized: "issue.source-access")
    case "SOURCE_SETTINGS_LOAD_FAILED", "SOURCE_SETTINGS_SAVE_FAILED":
      String(localized: "issue.source-settings")
    default:
      String(localized: "issue.generic")
    }
  }
}

extension ModelInstallation {
  var inventorySortName: String { identity.displayName }
  var inventorySourceTypeName: String { providerID.inventorySourceTypeName }
  var inventorySortSourceType: String { inventorySourceTypeName }
  var inventorySortFormat: String { variant.format.localizedName }
  var inventorySortState: String { state.localizedName }
  var inventorySortSize: Int64 { allocatedByteCount }
  var inventorySortAge: TimeInterval {
    earliestChangeTimestamp.map { -$0.value.timeIntervalSinceReferenceDate }
      ?? .greatestFiniteMagnitude
  }
  var inventorySortPath: String { rootURL.path }
}

enum InventoryCopyRepresentation: CaseIterable {
  case modelName
  case providerAndModelName
  case absoluteModelPath
}

struct InventoryTableRow: Identifiable {
  let installation: ModelInstallation
  let displayedByteCount: Int64
  let reclaimableByteCount: Int64

  var id: ModelInstallation.ID { installation.id }
  var sortName: String { installation.inventorySortName }
  var sortSourceType: String { installation.inventorySortSourceType }
  var sortFormat: String {
    [installation.inventorySortFormat, installation.variant.quantization]
      .compactMap { $0 }
      .joined(separator: " ")
  }
  var sortState: String { installation.inventorySortState }
  var sortSize: Int64 { displayedByteCount }
  var sortReclaimableSize: Int64 { reclaimableByteCount }
  var sortAge: TimeInterval { installation.inventorySortAge }
  var sortDate: TimeInterval {
    installation.earliestChangeTimestamp?.value.timeIntervalSinceReferenceDate
      ?? -.greatestFiniteMagnitude
  }
  var sortSource: String { installation.sourceID }
  var sortPath: String { installation.inventorySortPath }
}

let defaultInventorySortOrder = [
  KeyPathComparator(\InventoryTableRow.sortSize, order: .reverse)
]

struct InventoryTableColumnWidths: Equatable {
  static let minimum: CGFloat = 24

  let name: CGFloat
  let sourceType: CGFloat
  let format: CGFloat
  let state: CGFloat
  let size: CGFloat
  let reclaimableSize: CGFloat
  let age: CGFloat
  let date: CGFloat
  let source: CGFloat
  let path: CGFloat
}

func inventoryTableColumnWidths(
  rows: [InventoryTableRow],
  totalByteCount: Int64,
  sourceName: (ScanSource.ID) -> String,
  relativeTo referenceDate: Date = .now,
  measureText: (String) -> CGFloat = inventoryTableTextWidth
) -> InventoryTableColumnWidths {
  func width(for values: [String]) -> CGFloat {
    let contentWidth = values.map(measureText).max() ?? 0
    return max(InventoryTableColumnWidths.minimum, ceil(contentWidth) + 16)
  }

  return InventoryTableColumnWidths(
    name: width(for: rows.map(\.installation.identity.displayName)),
    sourceType: width(for: rows.map(\.installation.inventorySourceTypeName)),
    format: width(for: rows.map { formatAndQuantizationText($0.installation) }),
    state: width(for: rows.map(\.installation.state.localizedName)),
    size: width(
      for: rows.map { percentageText($0.displayedByteCount, of: totalByteCount) }
    ),
    reclaimableSize: width(for: rows.map { wholeByteCount($0.reclaimableByteCount) }),
    age: width(
      for: rows.map { installationAgeText($0.installation, relativeTo: referenceDate) }
    ),
    date: width(for: rows.map { firstChangeText($0.installation) }),
    source: width(for: rows.map { sourceName($0.installation.sourceID) }),
    path: width(for: rows.map(\.installation.rootURL.path))
  )
}

func inventoryTableTextWidth(_ text: String) -> CGFloat {
  (text as NSString).size(
    withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
  ).width
}

func inventoryTableRows(
  installations: [ModelInstallation],
  breakdown: InventoryStorageBreakdown
) -> [InventoryTableRow] {
  installations.map { installation in
    InventoryTableRow(
      installation: installation,
      displayedByteCount: breakdown.exclusiveByteCount(for: installation.id),
      reclaimableByteCount: breakdown.exclusiveByteCount(for: installation.id)
    )
  }
}

func inventoryCopyText(
  for installations: [ModelInstallation],
  representation: InventoryCopyRepresentation
) -> String {
  installations.map { installation in
    switch representation {
    case .modelName:
      installation.identity.displayName
    case .providerAndModelName:
      (installation.modelCard?.confidence == .confirmed ? installation.identity.family : nil)
        ?? "\(installation.providerID.rawValue)/\(installation.identity.displayName)"
    case .absoluteModelPath:
      installation.rootURL.standardizedFileURL.path
    }
  }
  .joined(separator: "\n")
}

func writeInventoryCopyTextToPasteboard(_ text: String) {
  guard !text.isEmpty else { return }
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}

func formatAndQuantizationText(_ installation: ModelInstallation) -> String {
  [installation.variant.format.localizedName, installation.variant.quantization]
    .compactMap { $0 }
    .joined(separator: " · ")
}

func firstChangeText(_ installation: ModelInstallation) -> String {
  guard let timestamp = installation.earliestChangeTimestamp else {
    return String(localized: "value.unknown")
  }
  return timestamp.value.formatted(date: .abbreviated, time: .omitted)
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
