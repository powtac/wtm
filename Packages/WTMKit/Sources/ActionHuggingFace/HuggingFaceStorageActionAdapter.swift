import Foundation
import WTMAdapterContracts
import WTMDomain
import WTMSecurity

public struct HuggingFaceStorageActionAdapter: StorageActionAdapter {
  public let id = ProviderID.huggingFace
  public let displayName = "Hugging Face"

  private let targetPolicy: DeletionTargetPolicy

  public init(targetPolicy: DeletionTargetPolicy = DeletionTargetPolicy()) {
    self.targetPolicy = targetPolicy
  }

  public func makeDeletionPlan(context: DeletionPlanningContext) async throws
    -> ProviderDeletionPlan
  {
    let selected = context.selectedInstallations.filter { $0.providerID == id }
    guard selected.count == context.selectedInstallations.count, !selected.isEmpty else {
      throw StorageActionAdapterError.invalidSelection
    }

    let selectedLocations = try selected.map { installation in
      try location(for: installation, context: context)
    }
    let selectedRevisionPaths = Set(
      selectedLocations.compactMap(\.revisionURL).map(canonicalNoFollowPath)
    )
    let linkGraph = try symbolicLinkGraph(sources: context.sources)
    var operationsByPath: [String: DeletionOperation] = [:]
    var retainedByID: [String: RetainedDeletionDependency] = [:]

    for location in selectedLocations {
      let installation = location.installation
      let source = location.source

      if let revisionURL = location.revisionURL {
        let regularBytes = installation.artifacts.reduce(Int64(0)) { total, artifact in
          let isSymbolicLink =
            (try? artifact.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink)
            ?? false
          return isSymbolicLink ? total : total + artifact.allocatedByteCount
        }
        try addTrashOperation(
          url: revisionURL,
          source: source,
          installationIDs: [installation.id],
          allocatedByteCount: regularBytes,
          operationsByPath: &operationsByPath
        )

        if let repositoryURL = location.repositoryURL,
          let revision = location.revision
        {
          for referenceURL in try matchingReferences(
            repositoryURL: repositoryURL,
            revision: revision,
            source: source
          ) {
            try addTrashOperation(
              url: referenceURL,
              source: source,
              installationIDs: [installation.id],
              allocatedByteCount: 0,
              operationsByPath: &operationsByPath
            )
          }
        }
      }

      for artifact in installation.artifacts {
        if artifact.isPartial, artifact.url.lastPathComponent.hasSuffix(".incomplete") {
          try addTrashOperation(
            url: artifact.url,
            source: source,
            installationIDs: [installation.id],
            allocatedByteCount: artifact.allocatedByteCount,
            operationsByPath: &operationsByPath
          )
          continue
        }

        guard let blobURL = try resolvedSymbolicLinkDestination(for: artifact.url) else { continue }
        let references = linkGraph[blobURL.resolvingSymlinksInPath().path] ?? []
        let remainingReferences = references.filter { referenceURL in
          let referencePath = canonicalNoFollowPath(referenceURL)
          return !selectedRevisionPaths.contains(where: { revisionPath in
            referencePath == revisionPath || referencePath.hasPrefix(revisionPath + "/")
          })
        }
        if remainingReferences.isEmpty {
          try addTrashOperation(
            url: blobURL,
            source: source,
            installationIDs: [installation.id],
            allocatedByteCount: artifact.allocatedByteCount,
            operationsByPath: &operationsByPath
          )
        } else {
          let dependency = RetainedDeletionDependency(
            id: "hf:retained:\(blobURL.path)",
            displayName: blobURL.lastPathComponent,
            allocatedByteCount: artifact.allocatedByteCount,
            reason: .remainingReference,
            installationIDs: [installation.id]
          )
          retainedByID[dependency.id] = merging(
            retainedByID[dependency.id],
            with: dependency
          )
        }
      }
    }

    let operations = Array(operationsByPath.values)
    guard !operations.isEmpty else { throw StorageActionAdapterError.noDeletableArtifacts }
    return ProviderDeletionPlan(
      providerID: id,
      models: selected.map(Self.summary),
      operations: operations,
      retainedDependencies: Array(retainedByID.values),
      warnings: [.externalUsageNotVerified, .freeSpaceIsEstimated]
    )
  }

  private func location(
    for installation: ModelInstallation,
    context: DeletionPlanningContext
  ) throws -> InstallationLocation {
    guard let source = context.source(for: installation.sourceID), source.isEnabled,
      source.accessState == .allowed
    else {
      throw StorageActionAdapterError.sourceUnavailable(installation.sourceID)
    }
    do {
      try targetPolicy.validateWritableVolume(containing: source.rootURL)
    } catch {
      throw StorageActionAdapterError.sourceUnavailable(installation.sourceID)
    }
    let sourcePrefix = source.rootURL.standardizedFileURL.path + "/"
    guard installation.rootURL.standardizedFileURL.path.hasPrefix(sourcePrefix) else {
      throw StorageActionAdapterError.pathOutsideSource
    }

    for artifact in installation.artifacts where artifact.isPartial {
      if artifact.url.lastPathComponent.hasSuffix(".incomplete") {
        return InstallationLocation(
          installation: installation,
          source: source,
          repositoryURL: nil,
          revisionURL: nil,
          revision: nil
        )
      }
    }

    let rootPath = installation.rootURL.standardizedFileURL.path
    guard let snapshotsRange = rootPath.range(of: "/snapshots/") else {
      throw StorageActionAdapterError.pathOutsideSource
    }
    let repositoryPath = String(rootPath[..<snapshotsRange.lowerBound])
    let remainder = rootPath[snapshotsRange.upperBound...]
    guard let revision = remainder.split(separator: "/").first.map(String.init),
      !revision.isEmpty
    else {
      throw StorageActionAdapterError.pathOutsideSource
    }
    let repositoryURL = URL(filePath: repositoryPath, directoryHint: .isDirectory)
    let revisionURL =
      repositoryURL
      .appending(path: "snapshots", directoryHint: .isDirectory)
      .appending(path: revision, directoryHint: .isDirectory)
    do {
      try targetPolicy.validateContainment(of: revisionURL, under: source.rootURL)
    } catch {
      throw StorageActionAdapterError.pathOutsideSource
    }
    return InstallationLocation(
      installation: installation,
      source: source,
      repositoryURL: repositoryURL,
      revisionURL: revisionURL,
      revision: revision
    )
  }

  private func symbolicLinkGraph(sources: [ScanSource]) throws -> [String: [URL]] {
    var graph: [String: [URL]] = [:]
    for source in sources where source.providerID == id && source.isEnabled {
      guard source.accessState == .allowed, source.rootIdentity != nil else {
        throw StorageActionAdapterError.sourceUnavailable(source.id)
      }
      let entries = try ReadOnlyDirectoryWalker().entries(
        under: source.rootURL,
        approvedBy: source
      )
      for entry in entries where entry.isSymbolicLink {
        guard entry.url.path.contains("/snapshots/"),
          let destination = try resolvedSymbolicLinkDestination(for: entry.url)
        else { continue }
        graph[destination.resolvingSymlinksInPath().path, default: []].append(entry.url)
      }
    }
    return graph
  }

  private func resolvedSymbolicLinkDestination(for url: URL) throws -> URL? {
    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values.isSymbolicLink == true else { return nil }
    let rawDestination = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    let destination: URL
    if rawDestination.hasPrefix("/") {
      destination = URL(filePath: rawDestination)
    } else {
      destination = URL(
        filePath: rawDestination,
        directoryHint: .notDirectory,
        relativeTo: url.deletingLastPathComponent()
      )
    }
    return destination.standardizedFileURL
  }

  private func matchingReferences(
    repositoryURL: URL,
    revision: String,
    source: ScanSource
  ) throws -> [URL] {
    let refsURL = repositoryURL.appending(path: "refs", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: refsURL.path) else { return [] }
    var matches: [URL] = []
    let entries = try ReadOnlyDirectoryWalker().entries(under: refsURL, approvedBy: source)
    for entry in entries where entry.isRegularFile {
      guard
        let data = try? FileMetadataReader().readData(
          from: entry.resolvedURL,
          maximumByteCount: 1_024,
          expectedIdentity: entry.resolvedIdentity
        ),
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(
          in: .whitespacesAndNewlines
        ),
        value == revision
      else { continue }
      matches.append(entry.url)
    }
    return matches
  }

  private func addTrashOperation(
    url: URL,
    source: ScanSource,
    installationIDs: Set<ModelInstallation.ID>,
    allocatedByteCount: Int64,
    operationsByPath: inout [String: DeletionOperation]
  ) throws {
    let path = url.standardizedFileURL.path
    let identity: DeletionFileIdentity
    guard let rootIdentity = source.rootIdentity else {
      throw StorageActionAdapterError.fileIdentityUnavailable
    }
    do {
      identity = try targetPolicy.captureIdentity(
        for: url,
        under: source.rootURL,
        volumeIdentity: source.volumeIdentity,
        expectedRootIdentity: rootIdentity
      )
    } catch {
      throw StorageActionAdapterError.fileIdentityUnavailable
    }
    let existing = operationsByPath[path]
    let combinedInstallationIDs = Set(existing?.installationIDs ?? []).union(installationIDs)
    let combinedByteCount = max(
      existing?.expectedReclaimableByteCount ?? 0,
      allocatedByteCount
    )
    let target = DeletionFileTarget(
      url: url,
      sourceID: source.id,
      sourceRootURL: source.rootURL,
      sourceRootIdentity: rootIdentity,
      identity: identity,
      allocatedByteCount: combinedByteCount,
      displayName: url.lastPathComponent
    )
    operationsByPath[path] = DeletionOperation(
      id: "hf:trash:\(operationPriority(for: url)):\(path)",
      providerID: id,
      installationIDs: Array(combinedInstallationIDs),
      reversibility: .trash,
      expectedReclaimableByteCount: combinedByteCount,
      payload: .trash(target)
    )
  }

  private func operationPriority(for url: URL) -> String {
    let path = url.standardizedFileURL.path
    if path.contains("/blobs/") { return "90-blob" }
    if path.contains("/refs/") { return "20-ref" }
    return "10-snapshot"
  }

  private func merging(
    _ existing: RetainedDeletionDependency?,
    with replacement: RetainedDeletionDependency
  ) -> RetainedDeletionDependency {
    RetainedDeletionDependency(
      id: replacement.id,
      displayName: replacement.displayName,
      allocatedByteCount: max(existing?.allocatedByteCount ?? 0, replacement.allocatedByteCount),
      reason: replacement.reason,
      installationIDs: Array(
        Set(existing?.installationIDs ?? []).union(replacement.installationIDs)
      )
    )
  }

  private func canonicalNoFollowPath(_ url: URL) -> String {
    url.deletingLastPathComponent().resolvingSymlinksInPath()
      .appending(path: url.lastPathComponent)
      .standardizedFileURL.path
  }

  private static func summary(_ installation: ModelInstallation) -> DeletionModelSummary {
    DeletionModelSummary(
      id: installation.id,
      displayName: installation.identity.displayName,
      providerID: installation.providerID,
      sourceID: installation.sourceID,
      artifactCount: installation.artifacts.count,
      allocatedByteCount: installation.allocatedByteCount
    )
  }
}

private struct InstallationLocation {
  let installation: ModelInstallation
  let source: ScanSource
  let repositoryURL: URL?
  let revisionURL: URL?
  let revision: String?
}
