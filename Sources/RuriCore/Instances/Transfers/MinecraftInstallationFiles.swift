import Foundation
import Darwin

enum MinecraftInstallationFiles {
    static func requireResource(_ file: URL, sha1: String, size: Int64) throws {
        guard DownloadManager.valid(file, item: .init(url: nil, destination: file, sha1: sha1, size: size)) else {
            throw RuriError.message("安装文件内容不一致，未覆盖现有文件：\(file.path)")
        }
    }
    static func copyResource(_ resource: MinecraftInstallationCopy.Resource, root: URL, validate: @Sendable () throws -> Void, progress: @Sendable (Int64) -> Void) async throws {
        let target = try LauncherPaths.safePath(resource.path, within: root)
        let lock = try await DownloadFileLock.acquire(for: target); defer { close(lock) }
        try validate()
        if FileManager.default.fileExists(atPath: target.path) {
            try requireResource(target, sha1: resource.sha1, size: resource.size); progress(resource.size); return
        }
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".ruri-partials/copy-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try RunDirectoryFileCopy.file(resource.source, to: temporary, validate: validate, progress: progress)
        try requireResource(temporary, sha1: resource.sha1, size: resource.size)
        var identity: RunDirectoryCopyJournal.Identity?
        do {
            try RunDirectoryFileCopy.publish(temporary, to: target, directory: false, created: { identity = $0 }, validate: validate, progress: { _ in })
        } catch {
            if identity?.matches(target) == true { try? FileManager.default.removeItem(at: target) }
            throw error
        }
    }
}
