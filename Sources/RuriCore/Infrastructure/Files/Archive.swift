import RuriLocalization
import Foundation
import ZIPFoundation

public enum SafeArchive {
    public static func verify(_ file: URL, maxBytes: Int64 = 16 * 1024 * 1024 * 1024) throws {
        let archive = try Archive(url: file, accessMode: .read)
        var total: Int64 = 0; var count = 0
        for entry in archive {
            try Task.checkCancellation(); count += 1
            guard count <= 150_000, Int64(entry.uncompressedSize) <= maxBytes - total else { throw RuriError.message(Messages.CoreArchive.countText1) }
            let crc = try archive.extract(entry) { chunk in
                total += Int64(chunk.count)
                guard total <= maxBytes else { throw RuriError.message(Messages.CoreArchive.countText1) }
            }
            guard crc == entry.checksum else { throw RuriError.message(Messages.CoreArchive.crcText1(String(describing: file.lastPathComponent), String(describing: entry.path))) }
        }
    }
    public static func extract(_ file: URL, to root: URL, allowSymlinks: Bool = false, excluding: [String] = [], maxBytes: Int64 = 16 * 1024 * 1024 * 1024) throws {
        let archive = try Archive(url: file, accessMode: .read)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var total: Int64 = 0; var count = 0
        for entry in archive {
            try Task.checkCancellation()
            count += 1
            guard count <= 150_000 else { throw RuriError.message(Messages.CoreArchive.countText2) }
            var path = entry.path
            while path.hasPrefix("./") { path.removeFirst(2) }
            if path.isEmpty || excluding.contains(where: { path.hasPrefix($0) }) { continue }
            let target = try LauncherPaths.safePath(path, within: root)
            guard entry.type != .symlink else { throw RuriError.message(Messages.CoreArchive.targetText1(String(describing: path))) }
            let size = Int64(entry.uncompressedSize)
            guard size <= maxBytes - total else { throw RuriError.message(Messages.CoreArchive.sizeText1) }
            if entry.type == .directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true); continue }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temp = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).extract")
            defer { try? FileManager.default.removeItem(at: temp) }
            guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw RuriError.message(Messages.CoreArchive.tempText1(String(describing: path))) }
            let handle = try FileHandle(forWritingTo: temp)
            do {
                let checksum = try archive.extract(entry, bufferSize: 128 * 1024) { data in
                    try Task.checkCancellation(); total += Int64(data.count)
                    guard total <= maxBytes else { throw RuriError.message(Messages.CoreArchive.sizeText1) }
                    try handle.write(contentsOf: data)
                }
                try handle.close()
                guard checksum == entry.checksum else { throw RuriError.message(Messages.CoreArchive.checksumText1(String(describing: path))) }
                guard rename(temp.path, target.path) == 0 else { throw RuriError.message(Messages.CoreArchive.checksumText2(String(describing: path))) }
            } catch { try? handle.close(); throw error }
        }
    }
}
