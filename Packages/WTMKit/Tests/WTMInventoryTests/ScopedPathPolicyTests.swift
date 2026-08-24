import Foundation
import Testing

@testable import WTMSecurity

@Test("A symlink cannot escape the configured root")
func symlinkEscapeIsRejected() throws {
  let root = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  let outside = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  defer {
    try? FileManager.default.removeItem(at: root)
    try? FileManager.default.removeItem(at: outside)
  }
  let link = root.appending(path: "escape")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

  let policy = ScopedPathPolicy(rootURL: root)

  #expect(throws: ScopedPathError.candidateOutsideRoot) {
    try policy.validate(link)
  }
}
