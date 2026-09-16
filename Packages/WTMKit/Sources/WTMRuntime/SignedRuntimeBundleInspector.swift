import Foundation
import Security
import WTMDomain

public enum RuntimeBundleError: Error, Equatable, Sendable {
  case invalidBundle
  case invalidSignature
  case externalResource
  case unsupportedBinary
  case identityChanged
}

/// A full resource seal, including nested native code, binds a frozen runtime closure.
public struct SignedRuntimeBundleInspector: Sendable {
  public init() {}

  public func inspect(_ url: URL, identifier: String) throws -> RuntimeSealedBundle {
    let root = url.standardizedFileURL
    guard root.isFileURL, root.pathExtension == "app", root.resolvingSymlinksInPath() == root,
      let bundle = Bundle(url: root), bundle.bundleIdentifier == identifier,
      let executable = bundle.executableURL,
      executable.deletingLastPathComponent() == root.appending(path: "Contents/MacOS")
    else { throw RuntimeBundleError.invalidBundle }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(root as CFURL, [], &code) == errSecSuccess, let code else {
      throw RuntimeBundleError.invalidSignature
    }
    let flags = SecCSFlags(
      rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
      throw RuntimeBundleError.invalidSignature
    }
    var info: CFDictionary?
    guard
      SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        == errSecSuccess,
      let values = info as? [String: Any],
      values[kSecCodeInfoIdentifier as String] as? String == identifier,
      let hash = values[kSecCodeInfoUnique as String] as? Data
    else { throw RuntimeBundleError.invalidSignature }
    let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
    guard
      let entries = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys,
        options: [], errorHandler: { _, _ in false })
    else { throw RuntimeBundleError.invalidBundle }
    var count = 0
    var bytes: Int64 = 0
    var binaries: [(URL, [String], [String])] = []
    for case let file as URL in entries {
      count += 1
      guard count <= 50_000 else { throw RuntimeBundleError.invalidBundle }
      let canonical = file.resolvingSymlinksInPath().standardizedFileURL
      guard canonical.pathComponents.starts(with: root.pathComponents) else {
        throw RuntimeBundleError.externalResource
      }
      let attributes = try file.resourceValues(forKeys: Set(keys))
      if attributes.isRegularFile == true, attributes.isSymbolicLink != true {
        bytes += Int64(attributes.fileSize ?? 0)
        guard bytes <= 2_147_483_648 else { throw RuntimeBundleError.invalidBundle }
        if let commands = try MachORuntimeDependencies.read(file) {
          binaries.append((file, commands.dependencies, commands.rpaths))
        }
      }
    }
    let executableDirectory = executable.deletingLastPathComponent()
    func localPath(_ value: String, loader: URL) throws -> URL {
      let base: URL
      let suffix: String
      if value == "@loader_path" || value.hasPrefix("@loader_path/") {
        base = loader.deletingLastPathComponent(); suffix = String(value.dropFirst(12))
      } else if value == "@executable_path" || value.hasPrefix("@executable_path/") {
        base = executableDirectory; suffix = String(value.dropFirst(16))
      } else {
        throw RuntimeBundleError.externalResource
      }
      let result = base.appending(
        path: suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      )
      .resolvingSymlinksInPath().standardizedFileURL
      guard result.pathComponents.starts(with: root.pathComponents) else {
        throw RuntimeBundleError.externalResource
      }
      return result
    }
    var rpaths: [URL] = []
    for (file, _, paths) in binaries {
      for path in paths { rpaths.append(try localPath(path, loader: file)) }
    }
    for (file, dependencies, _) in binaries {
      for dependency in dependencies {
        if dependency.hasPrefix("/usr/lib/") || dependency.hasPrefix("/System/Library/") {
          continue
        }
        let target: URL
        if dependency.hasPrefix("@rpath/") {
          let suffix = String(dependency.dropFirst(7))
          guard !suffix.split(separator: "/").contains(".."),
            let match = rpaths.map({ $0.appending(path: suffix) }).first(where: {
              FileManager.default.fileExists(atPath: $0.path)
            })
          else { throw RuntimeBundleError.externalResource }
          target = match
        } else {
          target = try localPath(dependency, loader: file)
        }
        guard target.resolvingSymlinksInPath().pathComponents.starts(with: root.pathComponents),
          FileManager.default.fileExists(atPath: target.path)
        else { throw RuntimeBundleError.externalResource }
      }
    }
    return RuntimeSealedBundle(
      bundleURL: root, identifier: identifier,
      codeDirectoryHash: hash.map { String(format: "%02x", $0) }.joined(),
      executableName: executable.lastPathComponent)
  }

  public func validate(_ expected: RuntimeSealedBundle, at url: URL? = nil) throws {
    let actual = try inspect(url ?? expected.bundleURL, identifier: expected.identifier)
    guard actual.codeDirectoryHash == expected.codeDirectoryHash,
      actual.executableName == expected.executableName
    else { throw RuntimeBundleError.identityChanged }
  }
}

/// Frozen runtime builds are thin arm64; reject fat/foreign Mach-O rather than guessing slices.
private enum MachORuntimeDependencies {
  static func read(_ url: URL) throws -> (dependencies: [String], rpaths: [String])? {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 1_048_576) ?? Data()
    guard data.count >= 4 else { return nil }
    func integer(_ offset: Int) throws -> UInt32 {
      guard offset >= 0, offset + 4 <= data.count else {
        throw RuntimeBundleError.unsupportedBinary
      }
      return data.withUnsafeBytes {
        UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
      }
    }
    let magic = try integer(0)
    guard magic == 0xfeedfacf else {
      if [
        UInt32(0xcafebabe), 0xbebafeca, 0xcafebabf, 0xbfbafeca, 0xfeedface, 0xcefaedfe, 0xcffaedfe,
      ].contains(magic) {
        throw RuntimeBundleError.unsupportedBinary
      }
      return nil
    }
    guard try integer(4) == 0x0100000c else { throw RuntimeBundleError.unsupportedBinary }
    let count = Int(try integer(16))
    let size = Int(try integer(20))
    guard count <= 4096, size <= data.count - 32 else { throw RuntimeBundleError.unsupportedBinary }
    var offset = 32
    var dependencies: [String] = []
    var rpaths: [String] = []
    for _ in 0..<count {
      let command = try integer(offset)
      let length = Int(try integer(offset + 4))
      guard length >= 8, offset + length <= 32 + size else {
        throw RuntimeBundleError.unsupportedBinary
      }
      if [UInt32(0xc), 0x80000018, 0x8000001f, 0x20, 0x80000023, 0x8000001c].contains(command) {
        let start = Int(try integer(offset + 8))
        guard start >= 12, start < length,
          let end = data[(offset + start)..<(offset + length)].firstIndex(of: 0),
          let path = String(data: data[(offset + start)..<end], encoding: .utf8), !path.isEmpty
        else { throw RuntimeBundleError.unsupportedBinary }
        if command == 0x8000001c { rpaths.append(path) } else { dependencies.append(path) }
      }
      offset += length
    }
    guard offset == 32 + size else { throw RuntimeBundleError.unsupportedBinary }
    return (dependencies, rpaths)
  }
}
