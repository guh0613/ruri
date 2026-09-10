import Foundation
import CryptoKit
import Darwin

/// File content alone does not describe a macOS file. In particular, removable
/// filesystems may represent these attributes with hidden AppleDouble files;
/// compare the logical attributes instead of that filesystem-specific encoding.
enum FileExtendedAttributes {
    struct Receipt: Codable, Equatable, Sendable {
        let name: String
        let size: Int
        let sha256: String
    }
    static let maximumValueBytes = 32 * 1024 * 1024
    private static let maximumNamesBytes = 64 * 1024
    // macOS manages provenance and sandbox access labels at the new location.
    // Native copying still handles them; do not forge or require equal labels.
    private static let systemLabels: Set<String> = ["com.apple.provenance", "com.apple.macl"]

    static func capture(_ url: URL) throws -> [Receipt] {
        let fd = try openFile(url); defer { close(fd) }
        var before = stat(); guard fstat(fd, &before) == 0 else { throw failure(url) }
        let names = try names(fd)
        guard names.count <= 256 else { throw RuriError.message("文件附加信息数量超过限制。") }
        var total = 0
        let result = try names.map { name -> Receipt in
            try Task.checkCancellation()
            let size = fgetxattr(fd, name, nil, 0, 0, 0)
            guard size >= 0, size <= maximumValueBytes else { throw RuriError.message("文件附加信息无法读取或超过大小限制：\(url.lastPathComponent) · \(name)") }
            total += size
            guard total <= 64 * 1024 * 1024 else { throw RuriError.message("单个文件的附加信息超过大小限制。") }
            var bytes = Data(count: max(1, size))
            let count = bytes.withUnsafeMutableBytes { fgetxattr(fd, name, $0.baseAddress, size, 0, 0) }
            guard count == size else { throw RuriError.message("文件附加信息在校验期间改变，请重试。") }
            bytes.count = size
            return .init(name: name, size: size, sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_ino == after.st_ino, before.st_dev == after.st_dev,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              try Self.names(fd) == names else { throw RuriError.message("文件附加信息在校验期间改变，请重试。") }
        try validate(result); return result
    }

    static func validate(_ receipts: [Receipt]) throws {
        guard receipts.count <= 256, receipts.map(\.name) == receipts.map(\.name).sorted(), Set(receipts.map(\.name)).count == receipts.count else { throw RuriError.message("文件附加信息的校验记录无效。") }
        var total = 0
        for entry in receipts {
            guard !entry.name.isEmpty, entry.name.utf8.count <= 255, !entry.name.contains("\0"), !systemLabels.contains(entry.name),
                  entry.size >= 0, entry.size <= maximumValueBytes, FileTreeManifest.validDigest(entry.sha256) else { throw RuriError.message("文件附加信息的校验记录无效。") }
            total += entry.size
        }
        guard total <= 64 * 1024 * 1024 else { throw RuriError.message("单个文件的附加信息超过大小限制。") }
    }

    static func copy(from source: URL, to destination: URL) throws {
        let input = try openFile(source); defer { close(input) }
        let output = try openFile(destination); defer { close(output) }
        try copy(from: input, to: output)
    }
    static func copy(from source: Int32, to destination: Int32) throws {
        try Task.checkCancellation()
        if fcopyfile(source, destination, nil, copyfile_flags_t(COPYFILE_XATTR)) != 0 {
            if errno == EPERM, isAttributeStorageFile(source) { return }
            throw RuriError.message("无法保留文件附加信息，原文件已保留。")
        }
    }

    /// Used only when rewriting a metadata file inside an owned staging tree.
    static func rewrite(_ data: Data, at file: URL) throws {
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".metadata-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let before = try capture(file)
        try data.write(to: temporary, options: .withoutOverwriting)
        try copy(from: file, to: temporary)
        guard try capture(temporary) == before, try capture(file) == before else { throw RuriError.message("实例元数据的附加信息在更新期间改变。") }
        guard rename(temporary.path, file.path) == 0 else { throw RuriError.message("无法更新实例元数据。") }
    }

    private static func names(_ fd: Int32) throws -> [String] {
        let size = flistxattr(fd, nil, 0, 0)
        if size < 0, errno == ENOTSUP { return [] }
        if size < 0, errno == EPERM, isAttributeStorageFile(fd) { return [] }
        guard size >= 0, size <= maximumNamesBytes else { throw RuriError.message("无法读取文件附加信息列表。") }
        if size == 0 { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        guard flistxattr(fd, &buffer, size, 0) == size, buffer.last == 0 else { throw RuriError.message("文件附加信息列表在读取期间改变。") }
        let bytes = buffer.map { UInt8(bitPattern: $0) }
        let names = try bytes.split(separator: 0).map { value -> String in
            guard let name = String(bytes: value, encoding: .utf8) else { throw RuriError.message("文件附加信息名称无效。") }; return name
        }
        return names.filter { !systemLabels.contains($0) }.sorted()
    }
    /// The macOS fallback refuses attributes on regular `._*` files to avoid
    /// recursive sidecars. Check the volume's native-xattr capability first;
    /// a permission error on APFS or on any other filename remains an error.
    private static func isAttributeStorageFile(_ fd: Int32) -> Bool {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard path.withUnsafeMutableBufferPointer({ fcntl(fd, F_GETPATH, $0.baseAddress!) }) == 0,
              let name = String(bytes: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)?.split(separator: "/").last,
              name.hasPrefix("._"), name.utf8.count > 2 else { return false }
        var request = attrlist()
        request.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)
        // Result length followed by the four capability and four validity words.
        var values = [UInt32](repeating: 0, count: 9)
        let result = values.withUnsafeMutableBytes { fgetattrlist(fd, &request, $0.baseAddress, $0.count, 0) }
        let index = Int(VOL_CAPABILITIES_INTERFACES), flag = UInt32(VOL_CAP_INT_EXTENDED_ATTR)
        return result == 0 && values[0] == 36 && values[5 + index] & flag != 0 && values[1 + index] & flag == 0
    }
    private static func openFile(_ url: URL) throws -> Int32 {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw failure(url) }
        var info = stat()
        guard fstat(fd, &info) == 0, [S_IFREG, S_IFDIR].contains(info.st_mode & S_IFMT) else { close(fd); throw failure(url) }
        return fd
    }
    private static func failure(_ url: URL) -> RuriError { .message("无法核对文件附加信息：\(url.lastPathComponent)") }
}
