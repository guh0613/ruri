import Foundation
import CryptoKit
import RuriLocalization

struct ContentFileDigest: Sendable {
    let sha1: String
    let sha512: String
    let md5: String
    let fingerprint: UInt32
    let size: Int64

    /// Hash compressed archive bytes, not ZIP entries. CurseForge ignores four
    /// whitespace bytes and seeds MurmurHash2 with the filtered length and 1.
    static func read(_ url: URL) throws -> Self {
        let before = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard before.isRegularFile == true, before.isSymbolicLink != true else { throw RuriError.message(Messages.ContentDetails.fileChanged(url.lastPathComponent)) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var sha1 = Insecure.SHA1(), sha512 = SHA512(), md5 = Insecure.MD5()
        var length: UInt64 = 0, size: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            sha1.update(data: data); sha512.update(data: data); md5.update(data: data)
            length += UInt64(data.reduce(0) { $0 + (ignored($1) ? 0 : 1) }); size += Int64(data.count)
        }
        try handle.seek(toOffset: 0)
        var murmur = Murmur(length: length)
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            for byte in data where !ignored(byte) { murmur.update(byte) }
        }
        let after = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate, size == Int64(after.fileSize ?? -1) else {
            throw RuriError.message(Messages.ContentDetails.fileChanged(url.lastPathComponent))
        }
        func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
        return Self(sha1: hex(sha1.finalize()), sha512: hex(sha512.finalize()), md5: hex(md5.finalize()), fingerprint: murmur.finalize(), size: size)
    }
    static func ignored(_ byte: UInt8) -> Bool { byte == 9 || byte == 10 || byte == 13 || byte == 32 }

    struct Murmur {
        private var hash: UInt32
        private var word: UInt32 = 0
        private var count: UInt32 = 0
        init(length: UInt64) { hash = UInt32(truncatingIfNeeded: length) ^ 1 }
        mutating func update(_ byte: UInt8) {
            word |= UInt32(byte) << (count * 8); count += 1
            if count == 4 {
                var value = word &* 0x5bd1e995
                value ^= value >> 24; value = value &* 0x5bd1e995
                hash = (hash &* 0x5bd1e995) ^ value
                word = 0; count = 0
            }
        }
        func finalize() -> UInt32 {
            var result = hash
            if count > 0 { result = (result ^ word) &* 0x5bd1e995 }
            result ^= result >> 13; result = result &* 0x5bd1e995; result ^= result >> 15
            return result
        }
    }
}
