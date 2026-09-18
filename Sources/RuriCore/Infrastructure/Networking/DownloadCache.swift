import Foundation

/// Verified reusable downloads stored by SHA-1, so retrying an import or
/// reinstalling a modpack does not fetch the same files again. On APFS the
/// copies are clones and cost no extra space.
public struct DownloadCache: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }
    public init(paths: LauncherPaths) { self.init(root: paths.cache.appendingPathComponent("objects")) }

    static func key(_ item: DownloadItem) -> String? {
        guard item.cacheable, let sha1 = item.sha1?.lowercased(), sha1.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { return nil }
        return sha1
    }
    func file(_ key: String) -> URL { root.appendingPathComponent(String(key.prefix(2))).appendingPathComponent(key) }

    /// Copies a cached file into place through `temporary`. The copy is verified
    /// again, so a damaged entry only costs a normal download.
    func restore(_ item: DownloadItem, through temporary: URL) async -> Bool {
        guard let key = Self.key(item) else { return false }
        let source = file(key)
        guard let info = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), info.isRegularFile == true, info.isSymbolicLink != true else { return false }
        try? FileManager.default.removeItem(at: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (try? FileManager.default.copyItem(at: source, to: temporary)) != nil else { return false }
        guard DownloadManager.valid(temporary, item: item) else { try? FileManager.default.removeItem(at: source); return false }
        return rename(temporary.path, item.destination.path) == 0
    }

    /// Keeps a verified download. Failures are ignored; the cache is only an optimization.
    func store(_ item: DownloadItem) async {
        guard let key = Self.key(item) else { return }
        let target = file(key)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: item.destination, to: temporary)
            _ = rename(temporary.path, target.path)
        } catch {}
    }
}
