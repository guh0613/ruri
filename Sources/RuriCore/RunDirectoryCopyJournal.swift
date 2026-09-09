import Foundation
import Darwin

public struct RunDirectoryCopyOwner: Sendable {
    public let transactionID: UUID
    public let instanceID: UUID
    public let instanceName: String
}

struct RunDirectoryCopyJournal: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case copying, publishing, committed, rollingBack }
    enum Area: String, Codable, Sendable { case game, metadata }
    struct Identity: Codable, Equatable, Sendable {
        let device: Int64
        let inode: UInt64
        let directory: Bool
        static func read(_ url: URL) throws -> Identity {
            var value = stat()
            guard lstat(url.path, &value) == 0, [S_IFREG, S_IFDIR].contains(value.st_mode & S_IFMT) else { throw RuriError.message("无法确认复制项目的文件身份：\(url.lastPathComponent)") }
            return Identity(device: Int64(value.st_dev), inode: UInt64(value.st_ino), directory: value.st_mode & S_IFMT == S_IFDIR)
        }
        func matches(_ url: URL) -> Bool { (try? Self.read(url)) == self }
    }
    struct Item: Codable, Sendable {
        let area: Area
        let name: String
        let identity: Identity
    }
    struct EmptyDirectory: Codable, Sendable { let area: Area; let path: String }
    var version = 1
    let id: UUID
    let original: GameInstance
    let target: GameRunDirectory
    let createdAt: Date
    var phase: Phase
    var items: [Item]
    let emptyDirectories: [EmptyDirectory]
    var owner: RunDirectoryCopyOwner { .init(transactionID: id, instanceID: original.id, instanceName: original.name) }
    static func root(paths: LauncherPaths, instanceID: UUID) throws -> URL {
        try LauncherPaths.safePath("run-directory-change", within: paths.instance(instanceID))
    }
    static func load(paths: LauncherPaths, instanceID: UUID) throws -> RunDirectoryCopyJournal {
        let root = try root(paths: paths, instanceID: instanceID)
        let record: Self = try RunDirectoryCopyGuard.decode(root.appendingPathComponent("transaction.json"), limit: 8_388_608)
        guard record.version == 1, record.original.id == instanceID, (record.original.runDirectory ?? .isolated) != record.target,
              record.items.count <= 4096, record.emptyDirectories.count <= 150_000, record.original.name.count <= 1024 else { throw RuriError.message("运行目录复制记录无效，工作副本已保留。") }
        var keys = Set<String>()
        for item in record.items {
            guard !item.name.isEmpty, item.name != ".", item.name != "..", !item.name.contains("/"), !item.name.contains("\\"), !item.name.contains("\0"),
                  item.identity.inode > 0, keys.insert(item.area.rawValue + "/" + item.name).inserted,
                  item.area != .metadata || ["content.json", "world-backups"].contains(item.name),
                  item.area != .game || ![".ruri", ".DS_Store", ".ruri-partials"].contains(item.name) else { throw RuriError.message("运行目录复制项目记录无效。") }
        }
        for directory in record.emptyDirectories {
            guard directory.area != .metadata || directory.path == "world-backups" || directory.path.hasPrefix("world-backups/") else { throw RuriError.message("运行目录复制记录包含无效的备份路径。") }
            _ = try LauncherPaths.safePath(directory.path, within: root)
            guard directory.path.split(separator: "/").first != ".ruri" else { throw RuriError.message("运行目录复制记录包含保留路径。") }
        }
        return record
    }
    func save(paths: LauncherPaths) throws {
        try paths.validateInstanceLocation(original.id)
        let directory = try Self.root(paths: paths, instanceID: original.id)
        let data = try JSONEncoder().encode(self)
        guard data.count <= 8_388_608 else { throw RuriError.message("运行目录复制记录超过大小限制。") }
        try data.write(to: directory.appendingPathComponent("transaction.json"), options: .atomic)
    }
    func incoming(_ item: Item, paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath("incoming/\(item.area.rawValue)/\(item.name)", within: Self.root(paths: paths, instanceID: original.id))
    }
    func destination(_ item: Item, paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath(item.name, within: item.area == .game ? paths.game(original.id) : paths.gameDataState(original.id))
    }
}

public enum RunDirectoryCopyGuard {
    private struct Marker: Codable {
        let version: Int
        let transactionID: UUID
        let instanceID: UUID
        let instanceName: String
        var owner: RunDirectoryCopyOwner { .init(transactionID: transactionID, instanceID: instanceID, instanceName: instanceName) }
    }
    static func markerURL(paths: LauncherPaths, instanceID: UUID) throws -> URL {
        try LauncherPaths.safePath("directory-change.json", within: paths.gameDataState(instanceID))
    }
    public static func hasPending(paths: LauncherPaths, instanceID: UUID) -> Bool {
        let own = paths.instance(instanceID).appendingPathComponent("run-directory-change")
        if FileManager.default.fileExists(atPath: own.path) { return true }
        return paths.runDirectory(for: instanceID) == .shared && FileManager.default.fileExists(atPath: paths.gameDataState(instanceID).appendingPathComponent("directory-change.json").path)
    }
    public static func owner(paths: LauncherPaths, instanceID: UUID) throws -> RunDirectoryCopyOwner? {
        if FileManager.default.fileExists(atPath: paths.instance(instanceID).appendingPathComponent("run-directory-change").path) {
            return try RunDirectoryCopyJournal.load(paths: paths, instanceID: instanceID).owner
        }
        guard paths.runDirectory(for: instanceID) == .shared else { return nil }
        return try sharedMarker(paths: paths, instanceID: instanceID)?.owner
    }
    static func requireAvailable(paths: LauncherPaths, instanceID: UUID, allowing id: UUID? = nil) throws {
        if FileManager.default.fileExists(atPath: paths.instance(instanceID).appendingPathComponent("run-directory-change").path) {
            guard let id, try RunDirectoryCopyJournal.load(paths: paths, instanceID: instanceID).id == id else { throw RuriError.message("此实例有未完成的运行目录复制，请在实例设置中恢复后继续。") }
        }
        try requireSharedAvailable(paths: paths, instanceID: instanceID, allowing: id)
    }
    static func requireSharedAvailable(paths: LauncherPaths, instanceID: UUID, allowing id: UUID? = nil) throws {
        guard paths.runDirectory(for: instanceID) == .shared, let marker = try sharedMarker(paths: paths, instanceID: instanceID) else { return }
        guard marker.transactionID == id, marker.instanceID == instanceID else { throw RuriError.message("“\(marker.instanceName)”正在调整此共享目录，或上次复制尚未恢复。请先在该实例的设置中处理。") }
    }
    private static func sharedMarker(paths: LauncherPaths, instanceID: UUID) throws -> Marker? {
        let url = try markerURL(paths: paths, instanceID: instanceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let marker: Marker = try decode(url, limit: 8192)
        guard marker.version == 1, marker.instanceName.count <= 1024 else { throw RuriError.message("共享目录的复制占用记录无效。") }
        return marker
    }
    static func mark(_ journal: RunDirectoryCopyJournal, paths: LauncherPaths) throws {
        guard paths.runDirectory(for: journal.original.id) == .shared else { return }
        let marker = Marker(version: 1, transactionID: journal.id, instanceID: journal.original.id, instanceName: journal.original.name)
        try JSONEncoder().encode(marker).write(to: markerURL(paths: paths, instanceID: journal.original.id), options: .atomic)
    }
    static func clear(_ journal: RunDirectoryCopyJournal, paths: LauncherPaths) throws {
        guard paths.runDirectory(for: journal.original.id) == .shared, let marker = try sharedMarker(paths: paths, instanceID: journal.original.id) else { return }
        guard marker.transactionID == journal.id, marker.instanceID == journal.original.id else { throw RuriError.message("共享目录的占用记录已经改变，未清除其他操作的记录。") }
        try FileManager.default.removeItem(at: markerURL(paths: paths, instanceID: journal.original.id))
    }
    static func decode<T: Decodable>(_ url: URL, limit: Int) throws -> T {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message("无法读取运行目录复制记录，请检查 \(url.path)。") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= limit else { throw RuriError.message("运行目录复制记录不是有效文件或超过大小限制。") }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw RuriError.message("运行目录复制记录超过大小限制。") }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
