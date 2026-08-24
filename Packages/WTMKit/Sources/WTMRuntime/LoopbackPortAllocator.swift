import Darwin
import Foundation

public enum LoopbackPortAllocatorError: Error, Equatable, Sendable {
  case invalidPort
  case socketCreationFailed
  case portUnavailable(UInt16)
  case addressLookupFailed
}

public struct LoopbackPortAllocator: Sendable {
  public init() {}

  public func availablePort(preferred: UInt16? = nil) throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw LoopbackPortAllocatorError.socketCreationFailed
    }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = (preferred ?? 0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard result == 0 else {
      throw LoopbackPortAllocatorError.portUnavailable(preferred ?? 0)
    }

    var boundAddress = sockaddr_in()
    var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let lookupResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
        getsockname(descriptor, socketAddress, &boundLength)
      }
    }
    guard lookupResult == 0 else {
      throw LoopbackPortAllocatorError.addressLookupFailed
    }
    let port = UInt16(bigEndian: boundAddress.sin_port)
    guard port > 0 else { throw LoopbackPortAllocatorError.invalidPort }
    return port
  }
}
