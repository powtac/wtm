import Darwin
import Foundation

public protocol RuntimeEndpointCorrelating: Sendable {
  func ownsListener(processIdentifier: Int32, endpoint: URL) async -> Bool
}

/// Correlates a loopback TCP listener with the exact process started by WTM.
/// Wrapper tools must `exec` their server; listeners owned only by descendants fail closed.
public struct DarwinProcessEndpointCorrelator: RuntimeEndpointCorrelating, Sendable {
  public init() {}

  public func ownsListener(processIdentifier: Int32, endpoint: URL) async -> Bool {
    guard endpoint.host == "127.0.0.1", let port = endpoint.port else { return false }
    let byteCount = proc_pidinfo(processIdentifier, PROC_PIDLISTFDS, 0, nil, 0)
    guard byteCount > 0 else { return false }
    let capacity = Int(byteCount) / MemoryLayout<proc_fdinfo>.stride
    var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
    let actualByteCount = descriptors.withUnsafeMutableBytes { buffer in
      proc_pidinfo(
        processIdentifier,
        PROC_PIDLISTFDS,
        0,
        buffer.baseAddress,
        Int32(buffer.count)
      )
    }
    guard actualByteCount > 0 else { return false }
    let count = Int(actualByteCount) / MemoryLayout<proc_fdinfo>.stride
    for descriptor in descriptors.prefix(count) where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
      var socket = socket_fdinfo()
      let socketByteCount = withUnsafeMutablePointer(to: &socket) {
        proc_pidfdinfo(
          processIdentifier,
          descriptor.proc_fd,
          PROC_PIDFDSOCKETINFO,
          $0,
          Int32(MemoryLayout<socket_fdinfo>.size)
        )
      }
      guard socketByteCount == MemoryLayout<socket_fdinfo>.size,
        socket.psi.soi_kind == SOCKINFO_TCP,
        socket.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
      else { continue }
      let localPort = UInt16(
        bigEndian: UInt16(
          truncatingIfNeeded:
            socket.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport))
      let localAddress = socket.psi.soi_proto.pri_tcp.tcpsi_ini.insi_laddr.ina_46.i46a_addr4.s_addr
      if localPort == UInt16(port), localAddress == inet_addr("127.0.0.1") { return true }
    }
    return false
  }
}
