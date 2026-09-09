import Foundation
import ZIPFoundation

public enum SafeArchive {
    public static func verify(_ file: URL, maxBytes: Int64 = 16 * 1024 * 1024 * 1024) throws {
        let archive = try Archive(url: file, accessMode: .read)
        var total: Int64 = 0; var count = 0
        for entry in archive {
            try Task.checkCancellation(); count += 1
            guard count <= 150_000, Int64(entry.uncompressedSize) <= maxBytes - total else { throw RuriError.message("压缩包超出校验大小限制") }
            let crc = try archive.extract(entry) { chunk in
                total += Int64(chunk.count)
                guard total <= maxBytes else { throw RuriError.message("压缩包超出校验大小限制") }
            }
            guard crc == entry.checksum else { throw RuriError.message("文件 CRC 校验失败：\(file.lastPathComponent)/\(entry.path)") }
        }
    }
    public static func extract(_ file: URL, to root: URL, allowSymlinks: Bool = false, excluding: [String] = [], maxBytes: Int64 = 16 * 1024 * 1024 * 1024) throws {
        let archive = try Archive(url: file, accessMode: .read)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var total: Int64 = 0; var count = 0
        for entry in archive {
            try Task.checkCancellation()
            count += 1
            guard count <= 150_000 else { throw RuriError.message("压缩包文件数量超出限制") }
            var path = entry.path
            while path.hasPrefix("./") { path.removeFirst(2) }
            if path.isEmpty || excluding.contains(where: { path.hasPrefix($0) }) { continue }
            let target = try LauncherPaths.safePath(path, within: root)
            guard entry.type != .symlink else { throw RuriError.message("压缩包不允许符号链接：\(path)") }
            let size = Int64(entry.uncompressedSize)
            guard size <= maxBytes - total else { throw RuriError.message("压缩包解压大小超出限制") }
            if entry.type == .directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true); continue }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temp = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).extract")
            defer { try? FileManager.default.removeItem(at: temp) }
            guard FileManager.default.createFile(atPath: temp.path, contents: nil) else { throw RuriError.message("无法解压文件：\(path)") }
            let handle = try FileHandle(forWritingTo: temp)
            do {
                let checksum = try archive.extract(entry, bufferSize: 128 * 1024) { data in
                    try Task.checkCancellation(); total += Int64(data.count)
                    guard total <= maxBytes else { throw RuriError.message("压缩包解压大小超出限制") }
                    try handle.write(contentsOf: data)
                }
                try handle.close()
                guard checksum == entry.checksum else { throw RuriError.message("压缩包文件校验失败：\(path)") }
                guard rename(temp.path, target.path) == 0 else { throw RuriError.message("无法保存解压文件：\(path)") }
            } catch { try? handle.close(); throw error }
        }
    }
}
