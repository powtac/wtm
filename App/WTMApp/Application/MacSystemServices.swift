import AppKit
import Foundation

@MainActor
protocol FolderSelecting {
  func chooseFolder() -> URL?
}

@MainActor
struct MacFolderSelector: FolderSelecting {
  func chooseFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = String(localized: "source.choose.action")
    panel.message = String(localized: "source.choose.message")
    return panel.runModal() == .OK ? panel.url : nil
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
