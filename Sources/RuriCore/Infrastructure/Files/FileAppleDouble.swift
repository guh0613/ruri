import RuriLocalization
import Foundation
import Darwin

/// A dot-underscore filename alone is not metadata. Only omit the native macOS
/// AppleDouble layout when its values are also readable on the companion file.
/// Unrecognized layouts and detached sidecars remain ordinary files.
enum FileAppleDouble {
    static func isRepresented(_ sidecar: URL, by companion: URL) throws -> Bool {
        let fd = open(sidecar.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_size >= 82, before.st_size <= 64 * 1024 * 1024 + 65_536 else { return false }
        let header = try handle.read(upToCount: 82) ?? Data()
        guard header.count == 82, number(header, 0) == 0x00051607, number(header, 4) == 0x00020000,
              Data(header[8..<24]) == Data("Mac OS X        ".utf8), number(header, 24, 2) == 2,
              number(header, 26) == 9, number(header, 30) == 50, number(header, 38) == 2 else { return false }
        let finderLength = number(header, 34), resourceOffset = number(header, 42), resourceLength = number(header, 46)
        guard finderLength >= 32, resourceOffset == 50 + finderLength,
              resourceOffset <= before.st_size, resourceLength == Int(before.st_size) - resourceOffset else { return false }
        try Task.checkCancellation()
        var data = header
        data.append(try handle.read(upToCount: Int(before.st_size) - data.count) ?? Data())
        guard data.count == before.st_size else { return false }
        let peer = open(companion.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard peer >= 0 else { return false }; defer { close(peer) }
        var peerInfo = stat()
        guard fstat(peer, &peerInfo) == 0, [S_IFREG, S_IFDIR].contains(peerInfo.st_mode & S_IFMT) else { return false }
        let finder = Data(data[50..<82]), resource = Data(data[resourceOffset..<data.count])
        guard matches(finder, name: "com.apple.FinderInfo", fd: peer, absent: finder.allSatisfy { $0 == 0 }),
              matches(resource, name: "com.apple.ResourceFork", fd: peer, absent: resource.isEmpty || resource == emptyResourceFork) else { return false }
        if finderLength > 32 {
            guard resourceOffset >= 120, number(data, 84) == 0x41545452,
                  number(data, 92) == resourceOffset, number(data, 116, 2) == 0 else { return false }
            let start = number(data, 96), length = number(data, 100), count = number(data, 118, 2)
            guard start >= 120, start <= resourceOffset, length <= resourceOffset - start, count <= 256 else { return false }
            var position = 120, names: Set<String> = [], ranges: [Range<Int>] = []
            for _ in 0..<count {
                try Task.checkCancellation()
                guard position + 11 <= min(start, 65_536) else { return false }
                let offset = number(data, position), size = number(data, position + 4), nameLength = number(data, position + 10, 1)
                let next = (position + 11 + nameLength + 3) & ~3
                guard nameLength > 1, next <= min(start, 65_536), number(data, position + 8, 2) == 0,
                      data[position + 11 + nameLength - 1] == 0, offset >= start, offset <= start + length,
                      size <= start + length - offset, size <= FileExtendedAttributes.maximumValueBytes,
                      let name = String(data: data[(position + 11)..<(position + 10 + nameLength)], encoding: .utf8),
                      !name.contains("\0"), names.insert(name).inserted,
                      !["com.apple.FinderInfo", "com.apple.ResourceFork"].contains(name) else { return false }
                let range = offset..<(offset + size)
                guard !ranges.contains(where: { $0.overlaps(range) }), matches(Data(data[range]), name: name, fd: peer) else { return false }
                ranges.append(range); position = next
            }
        }
        var after = stat(), location = stat(), peerAfter = stat()
        guard fstat(fd, &after) == 0, lstat(sidecar.path, &location) == 0, fstat(peer, &peerAfter) == 0,
              unchanged(before, after), unchanged(before, location), unchanged(peerInfo, peerAfter) else {
            throw RuriError.message(Messages.CoreFileAppleDouble.fileChangedDuringEnumeration)
        }
        return true
    }

    private static func number(_ data: Data, _ offset: Int, _ size: Int = 4) -> Int {
        data[offset..<(offset + size)].reduce(0) { ($0 << 8) | Int($1) }
    }
    private static func matches(_ data: Data, name: String, fd: Int32, absent: Bool = false) -> Bool {
        let size = fgetxattr(fd, name, nil, 0, 0, 0)
        if size < 0 { return errno == ENOATTR && absent }
        guard size == data.count, size <= FileExtendedAttributes.maximumValueBytes else { return false }
        var actual = Data(count: max(1, size))
        guard actual.withUnsafeMutableBytes({ fgetxattr(fd, name, $0.baseAddress, size, 0, 0) }) == size else { return false }
        actual.count = size; return actual == data
    }
    private static func unchanged(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_size == b.st_size &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
    private static let emptyResourceFork: Data = {
        var value = Data(repeating: 0, count: 286)
        let header: [UInt8] = [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 30]
        value.replaceSubrange(0..<16, with: header)
        value.replaceSubrange(256..<272, with: header)
        let marker = Data("This resource fork intentionally left blank   ".utf8)
        value.replaceSubrange(16..<(16 + marker.count), with: marker)
        value.replaceSubrange(280..<286, with: [0, 28, 0, 30, 255, 255])
        return value
    }()
}
