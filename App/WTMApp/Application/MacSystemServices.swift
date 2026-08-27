import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers
import WTMDomain
import WTMPersistence

@MainActor
protocol LaunchAtLoginManaging {
  var isEnabled: Bool { get }
  func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct MacLaunchAtLoginManager: LaunchAtLoginManaging {
  var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}

@MainActor
protocol FolderSelecting {
  func chooseFolder(startingAt url: URL?) -> URL?
}

@MainActor
struct MacFolderSelector: FolderSelecting {
  func chooseFolder(startingAt url: URL? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = String(localized: "source.choose.action")
    panel.message = String(localized: "source.choose.message")
    panel.directoryURL = url
    return panel.runModal() == .OK ? panel.url : nil
  }
}

@MainActor
protocol ExecutableSelecting {
  func chooseExecutable(startingAt url: URL?) -> URL?
}

@MainActor
struct MacExecutableSelector: ExecutableSelecting {
  func chooseExecutable(startingAt url: URL? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = String(localized: "tool.choose.action")
    panel.message = String(localized: "tool.choose.message")
    panel.directoryURL = url?.deletingLastPathComponent()
    return panel.runModal() == .OK ? panel.url : nil
  }
}

@MainActor
protocol ToolManifestDocumenting {
  func importDefinition() throws -> ToolDefinition?
  func exportDefinition(_ definition: ToolDefinition) throws
}

@MainActor
struct JSONToolManifestDocument: ToolManifestDocumenting {
  func importDefinition() throws -> ToolDefinition? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.json]
    panel.prompt = String(localized: "tool.import.action")
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    let manifest = try JSONDecoder().decode(
      ToolDefinitionManifest.self,
      from: Data(contentsOf: url, options: [.mappedIfSafe])
    )
    guard manifest.schemaVersion == ToolDefinitionManifest.currentSchemaVersion else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return manifest.definition
  }

  func exportDefinition(_ definition: ToolDefinition) throws {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = "\(definition.displayName)-tool.json"
    panel.prompt = String(localized: "tool.export.action")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(
      ToolDefinitionManifest(
        definition: ToolDefinitionManifestPolicy.definitionForExport(
          definition,
          homeDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
        )
      )
    )
    try data.write(to: url, options: [.atomic])
  }
}

struct MountedVolumeInfo: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let rootURL: URL
  let totalByteCount: Int64?
  let availableByteCount: Int64?
  let fileSystem: String
  let isReadOnly: Bool
}

protocol VolumeCataloging: Sendable {
  func mountedVolumes() -> [MountedVolumeInfo]
}

struct MacVolumeCatalog: VolumeCataloging {
  func mountedVolumes() -> [MountedVolumeInfo] {
    let baseKeys: Set<URLResourceKey> = [
      .volumeNameKey,
      .volumeTotalCapacityKey,
      .volumeLocalizedFormatDescriptionKey,
      .volumeIsReadOnlyKey,
      .volumeIdentifierKey,
      .volumeUUIDStringKey,
    ]
    return
      (FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(baseKeys),
        options: [.skipHiddenVolumes]
      ) ?? [])
      .compactMap { url in
        guard let values = try? url.resourceValues(forKeys: baseKeys) else { return nil }
        let identifier =
          values.volumeUUIDString
          ?? values.volumeIdentifier.map { String(describing: $0) }
          ?? url.standardizedFileURL.path
        let isReadOnly = values.volumeIsReadOnly ?? false
        let availableByteCount: Int64?
        if isReadOnly {
          availableByteCount = nil
        } else {
          availableByteCount = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
          ).volumeAvailableCapacityForImportantUsage
        }
        return MountedVolumeInfo(
          id: identifier,
          name: values.volumeName ?? url.lastPathComponent,
          rootURL: url.standardizedFileURL,
          totalByteCount: values.volumeTotalCapacity.map(Int64.init),
          availableByteCount: availableByteCount,
          fileSystem: values.volumeLocalizedFormatDescription ?? String(localized: "value.unknown"),
          isReadOnly: isReadOnly
        )
      }
      .sorted { left, right in
        left.name.localizedStandardCompare(right.name) == .orderedAscending
      }
  }
}

@MainActor
protocol FileRevealing {
  func reveal(_ url: URL)
}

@MainActor
struct MacFileRevealer: FileRevealing {
  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
