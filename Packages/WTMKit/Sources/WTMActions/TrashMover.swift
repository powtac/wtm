import Foundation

public protocol TrashMoving: Sendable {
  func moveToTrash(_ url: URL) async throws
}

public struct SystemTrashMover: TrashMoving {
  public init() {}

  public func moveToTrash(_ url: URL) async throws {
    var resultingURL: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
  }
}
