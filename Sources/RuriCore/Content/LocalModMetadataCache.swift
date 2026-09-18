import Foundation
import Darwin

/// A presentation cache only. Installation and removal still validate the real files.
/// File identity survives an enable/disable rename; changed or replaced JARs miss the cache.
struct LocalContentStamp: Equatable, Sendable {
    let key: String
    let size: Int64

    static func read(_ url: URL) -> Self? {
        var value = stat()
        guard url.withUnsafeFileSystemRepresentation({ pointer in
            pointer.map { lstat($0, &value) } ?? -1
        }) == 0, value.st_mode & S_IFMT == S_IFREG else { return nil }
        return Self(key: "\(value.st_dev):\(value.st_ino):\(value.st_birthtimespec.tv_sec):\(value.st_birthtimespec.tv_nsec):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec)", size: value.st_size)
    }
}

/// All mutable state is protected by `lock`; archive parsing runs outside it.
final class LocalModMetadataCache: @unchecked Sendable {
    struct Record: Codable {
        let metadata: LocalModMetadata?
        var accessed: Date
        var cost: Int {
            guard let metadata else { return 256 }
            return 512 + [metadata.id, metadata.name, metadata.version, metadata.summary, metadata.homepage?.absoluteString, metadata.iconPath]
                .compactMap { $0 }.reduce(0) { $0 + $1.utf8.count } + metadata.authors.reduce(0) { $0 + $1.utf8.count }
        }
    }
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        let stores = NSCache<NSURL, LocalModMetadataCache>()
        init() { stores.countLimit = 8 }
    }
    private static let registry = Registry()
    static func shared(in directory: URL) -> LocalModMetadataCache {
        let key = directory.standardizedFileURL as NSURL
        registry.lock.lock(); defer { registry.lock.unlock() }
        if let existing = registry.stores.object(forKey: key) { return existing }
        let store = LocalModMetadataCache(directory: directory)
        registry.stores.setObject(store, forKey: key)
        return store
    }

    private let lock = NSLock()
    private let url: URL
    private var records: [String: Record] = [:]
    private var cost = 0
    private var dirty = false
    private static let byteLimit = 16 * 1024 * 1024

    private init(directory: URL) {
        // Bump the schema when the metadata parser's interpretation changes.
        url = directory.appendingPathComponent("local-mod-metadata-v1.json")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.byteLimit,
           let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
            records = saved
            cost = records.values.reduce(0) { $0 + $1.cost }
            trim()
        }
    }

    func cached(_ stamp: LocalContentStamp) -> Record? {
        lock.lock(); defer { lock.unlock() }
        guard var record = records[stamp.key] else { return nil }
        record.accessed = Date()
        records[stamp.key] = record
        return record
    }

    func resolve(_ url: URL, stamp: LocalContentStamp) -> Record? {
        guard !Task.isCancelled, LocalContentStamp.read(url) == stamp else { return nil }
        if let hit = cached(stamp) { return hit }
        let metadata = LocalModMetadata.read(url)
        // Do not save a partial/cancelled parse or metadata for a file replaced mid-read.
        guard !Task.isCancelled, LocalContentStamp.read(url) == stamp else { return nil }
        let record = Record(metadata: metadata, accessed: Date())
        lock.lock(); defer { lock.unlock() }
        cost -= records[stamp.key]?.cost ?? 0
        records[stamp.key] = record; cost += record.cost; dirty = true
        trim()
        return record
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        guard dirty else { return }
        do {
            let data = try JSONEncoder().encode(records)
            guard data.count <= Self.byteLimit else { return }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            dirty = false
        } catch { /* The list remains usable when the disposable cache cannot be saved. */ }
    }

    private func trim() {
        guard records.count > 4096 || cost > Self.byteLimit else { return }
        for (key, record) in records.sorted(by: { $0.value.accessed < $1.value.accessed }) {
            records.removeValue(forKey: key); cost -= record.cost; dirty = true
            if records.count <= 3072 && cost <= Self.byteLimit * 3 / 4 { break }
        }
    }
}
