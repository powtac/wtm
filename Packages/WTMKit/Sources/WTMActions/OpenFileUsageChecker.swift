import Darwin
import Foundation
import WTMDomain

public protocol OpenFileUsageChecking: Sendable {
  func openTargetPaths(in targets: [DeletionFileTarget]) async -> Set<String>
}

/// Best-effort local process inspection for open files that overlap deletion targets.
///
/// macOS may deny information about protected or other-user processes. Provider-specific
/// checks remain authoritative where available; any positively identified open target blocks.
public struct SystemOpenFileUsageChecker: OpenFileUsageChecking {
  public init() {}

  public func openTargetPaths(in targets: [DeletionFileTarget]) async -> Set<String> {
    guard !targets.isEmpty else { return [] }
    let targetPaths = targets.map { $0.url.standardizedFileURL.path }
    let openPaths = Self.openFilePaths()
    return Set(
      targetPaths.filter { targetPath in
        openPaths.contains { openPath in
          openPath == targetPath || openPath.hasPrefix(targetPath + "/")
        }
      }
    )
  }

  private static func openFilePaths() -> Set<String> {
    let pidByteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard pidByteCount > 0 else { return [] }
    var processIDs = [pid_t](
      repeating: 0,
      count: Int(pidByteCount) / MemoryLayout<pid_t>.stride
    )
    let populatedPIDBytes = processIDs.withUnsafeMutableBytes { buffer in
      proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
    }
    guard populatedPIDBytes > 0 else { return [] }
    let populatedPIDCount = min(
      Int(populatedPIDBytes) / MemoryLayout<pid_t>.stride,
      processIDs.count
    )

    var paths: Set<String> = []
    for processID in processIDs.prefix(populatedPIDCount) where processID > 0 {
      paths.formUnion(openFilePaths(processID: processID))
    }
    return paths
  }

  private static func openFilePaths(processID: pid_t) -> Set<String> {
    let descriptorByteCount = proc_pidinfo(processID, PROC_PIDLISTFDS, 0, nil, 0)
    guard descriptorByteCount > 0 else { return [] }
    var descriptors = [proc_fdinfo](
      repeating: proc_fdinfo(),
      count: Int(descriptorByteCount) / MemoryLayout<proc_fdinfo>.stride
    )
    let populatedDescriptorBytes = descriptors.withUnsafeMutableBytes { buffer in
      proc_pidinfo(
        processID,
        PROC_PIDLISTFDS,
        0,
        buffer.baseAddress,
        Int32(buffer.count)
      )
    }
    guard populatedDescriptorBytes > 0 else { return [] }
    let populatedDescriptorCount = min(
      Int(populatedDescriptorBytes) / MemoryLayout<proc_fdinfo>.stride,
      descriptors.count
    )

    var paths: Set<String> = []
    for descriptor in descriptors.prefix(populatedDescriptorCount)
    where descriptor.proc_fdtype == PROX_FDTYPE_VNODE {
      var information = vnode_fdinfowithpath()
      let byteCount = withUnsafeMutablePointer(to: &information) { pointer in
        proc_pidfdinfo(
          processID,
          descriptor.proc_fd,
          PROC_PIDFDVNODEPATHINFO,
          pointer,
          Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        )
      }
      guard byteCount == MemoryLayout<vnode_fdinfowithpath>.size else { continue }
      let path = withUnsafePointer(to: &information.pvip.vip_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
          String(cString: $0)
        }
      }
      if !path.isEmpty { paths.insert(URL(filePath: path).standardizedFileURL.path) }
    }
    return paths
  }
}
