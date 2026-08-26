import Foundation
import Testing
import WTMDomain

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

@Test("Replacing an approved source root with a symlink blocks scanning")
func replacedApprovedRootBlocksScanning() throws {
  let fixture = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  let root = fixture.appending(path: "approved", directoryHint: .isDirectory)
  let original = fixture.appending(path: "original", directoryHint: .isDirectory)
  let redirected = fixture.appending(path: "redirected", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: true)
  try Data("private".utf8).write(to: redirected.appending(path: "model.gguf"))
  defer { try? FileManager.default.removeItem(at: fixture) }

  let identity = try SourceRootPolicy().capture(rootURL: root)
  let source = ScanSource(
    id: "approved",
    displayName: "Approved",
    providerID: .manual,
    rootURL: root,
    rootIdentity: identity,
    accessState: .allowed,
    isEnabled: true
  )
  try FileManager.default.moveItem(at: root, to: original)
  try FileManager.default.createSymbolicLink(at: root, withDestinationURL: redirected)

  #expect(throws: ScopedPathError.sourceIdentityChanged) {
    try ReadOnlyDirectoryWalker().entries(under: root, approvedBy: source)
  }
}

@Test("Replacing an approved root ancestor invalidates a cleanup target")
func replacedApprovedAncestorBlocksCleanup() throws {
  let fixture = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  let container = fixture.appending(path: "container", directoryHint: .isDirectory)
  let original = fixture.appending(path: "original", directoryHint: .isDirectory)
  let root = container.appending(path: "models", directoryHint: .isDirectory)
  let target = root.appending(path: "model.gguf")
  let redirectedContainer = fixture.appending(path: "redirected", directoryHint: .isDirectory)
  let redirectedRoot = redirectedContainer.appending(path: "models", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  try Data("approved".utf8).write(to: target)
  try FileManager.default.createDirectory(at: redirectedRoot, withIntermediateDirectories: true)
  try Data("private".utf8).write(to: redirectedRoot.appending(path: "model.gguf"))
  defer { try? FileManager.default.removeItem(at: fixture) }

  let rootIdentity = try SourceRootPolicy().capture(rootURL: root)
  let policy = DeletionTargetPolicy()
  let targetIdentity = try policy.captureIdentity(
    for: target,
    under: root,
    volumeIdentity: nil,
    expectedRootIdentity: rootIdentity
  )
  let deletionTarget = DeletionFileTarget(
    url: target,
    sourceID: "approved",
    sourceRootURL: root,
    sourceRootIdentity: rootIdentity,
    identity: targetIdentity,
    allocatedByteCount: 1,
    displayName: "model.gguf"
  )
  try FileManager.default.moveItem(at: container, to: original)
  try FileManager.default.createSymbolicLink(at: container, withDestinationURL: redirectedContainer)

  #expect(throws: SourceRootPolicyError.identityChanged) {
    try policy.revalidate(deletionTarget)
  }
}

@Test("Replacing a target ancestor with an escaping symlink blocks cleanup")
func replacedTargetAncestorBlocksCleanup() throws {
  let fixture = FileManager.default.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  let root = fixture.appending(path: "models", directoryHint: .isDirectory)
  let directory = root.appending(path: "selected", directoryHint: .isDirectory)
  let backup = root.appending(path: "selected-backup", directoryHint: .isDirectory)
  let target = directory.appending(path: "model.gguf")
  let outside = fixture.appending(path: "private", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
  try Data("approved".utf8).write(to: target)
  try Data("private".utf8).write(to: outside.appending(path: "model.gguf"))
  defer { try? FileManager.default.removeItem(at: fixture) }

  let rootIdentity = try SourceRootPolicy().capture(rootURL: root)
  let policy = DeletionTargetPolicy()
  let targetIdentity = try policy.captureIdentity(
    for: target,
    under: root,
    volumeIdentity: nil,
    expectedRootIdentity: rootIdentity
  )
  let deletionTarget = DeletionFileTarget(
    url: target,
    sourceID: "approved",
    sourceRootURL: root,
    sourceRootIdentity: rootIdentity,
    identity: targetIdentity,
    allocatedByteCount: 1,
    displayName: "model.gguf"
  )
  try FileManager.default.moveItem(at: directory, to: backup)
  try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)

  #expect(throws: ScopedPathError.candidateOutsideRoot) {
    try policy.revalidate(deletionTarget)
  }
}
