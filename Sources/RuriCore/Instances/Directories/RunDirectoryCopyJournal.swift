import RuriLocalization
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
        var volumeUUID: String?
        static func read(_ url: URL) throws -> Identity {
            var value = stat()
            guard lstat(url.path, &value) == 0, [S_IFREG, S_IFDIR].contains(value.st_mode & S_IFMT) else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.sourceIdentityUnknown(url.lastPathComponent)) }
            return Identity(device: Int64(value.st_dev), inode: UInt64(value.st_ino), directory: value.st_mode & S_IFMT == S_IFDIR,
                            volumeUUID: try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)
        }
        func matches(_ url: URL) -> Bool {
            guard let candidate = try? Self.read(url), candidate.inode == inode, candidate.directory == directory else { return false }
            // Device numbers belong to a mount session. A removable volume can
            // receive a different one when it reconnects during recovery.
            if let volumeUUID { return candidate.volumeUUID == volumeUUID }
            return candidate.device == device // Journals written by older builds.
        }
    }
    struct Item: Codable, Sendable {
        let area: Area
        let name: String
        let identity: Identity
        var publishedIdentity: Identity?
    }
    struct EmptyDirectory: Codable, Sendable { let area: Area; let path: String }
    var version = 4
    let id: UUID
    let original: GameInstance
    let target: GameRunDirectory
    var targetCustomDirectory: CustomRunDirectory?
    var stagingOnTarget: Bool?
    let createdAt: Date
    var phase: Phase
    var items: [Item]
    let emptyDirectories: [EmptyDirectory]
    var owner: RunDirectoryCopyOwner { .init(transactionID: id, instanceID: original.id, instanceName: original.name) }
    static func root(paths: LauncherPaths, instanceID: UUID) throws -> URL {
        try LauncherPaths.safePath("run-directory-change", within: paths.instance(instanceID))
    }
    static func load(paths: LauncherPaths, instanceID: UUID, recordDirectory: URL? = nil) throws -> RunDirectoryCopyJournal {
        let root = try recordDirectory ?? root(paths: paths, instanceID: instanceID)
        let record: Self = try RunDirectoryCopyGuard.decode(root.appendingPathComponent("transaction.json"), limit: 8_388_608)
        var differentLocation = (record.original.runDirectory ?? .isolated) != record.target
        if !differentLocation, record.target == .custom, let source = record.original.customRunDirectory, let target = record.targetCustomDirectory { differentLocation = !source.isSameLocation(as: target) }
        guard (1...4).contains(record.version), record.original.id == instanceID, differentLocation,
              record.items.count <= 4096, record.emptyDirectories.count <= 150_000, record.original.name.count <= 1024 else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidRecord) }
        if record.target == .custom {
            guard let custom = record.targetCustomDirectory ?? record.original.customRunDirectory else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.missingCustomTarget) }
            try custom.validateConfiguration()
        }
        try record.targetPaths(paths).validateDirectoryConfiguration()
        guard record.stagingOnTarget != true || record.target == .custom else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidWorkspace) }
        let reserved = Set(MinecraftGameDataFiles.reservedNames(paths: record.targetPaths(paths), instanceID: instanceID).map(MinecraftGameDataFiles.key))
        var keys = Set<String>()
        for item in record.items {
            guard !item.name.isEmpty, item.name != ".", item.name != "..", !item.name.contains("/"), !item.name.contains("\\"), !item.name.contains("\0"),
                  item.identity.inode > 0, item.identity.volumeUUID.map({ !$0.isEmpty && $0.count <= 128 }) ?? true,
                  keys.insert(item.area.rawValue + "/" + item.name).inserted,
                  item.area != .metadata || ["content.json", "world-backups"].contains(item.name),
                  item.area != .game || ![".ruri", ".DS_Store", ".ruri-partials"].contains(item.name) else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidKeys) }
            if let published = item.publishedIdentity {
                guard record.version >= 3, published.inode > 0, published.directory == item.identity.directory,
                      published.volumeUUID.map({ !$0.isEmpty && $0.count <= 128 }) ?? true else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidPublishedIdentity) }
            }
            if record.version >= 4, item.area == .game, reserved.contains(MinecraftGameDataFiles.key(item.name)) {
                throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.installedFilesPreserved)
            }
        }
        for directory in record.emptyDirectories {
            guard directory.area != .metadata || directory.path == "world-backups" || directory.path.hasPrefix("world-backups/") else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidBackupPath) }
            _ = try LauncherPaths.safePath(directory.path, within: root)
            guard directory.path.split(separator: "/").first != ".ruri" else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.retainedPath) }
            if record.version >= 4, directory.area == .game, let first = directory.path.split(separator: "/").first,
               reserved.contains(MinecraftGameDataFiles.key(String(first))) { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.targetDirectoryPresent) }
        }
        return record
    }
    func save(paths: LauncherPaths, at preparedDirectory: URL? = nil) throws {
        try paths.validateInstanceLocation(original.id)
        let directory = try preparedDirectory ?? Self.root(paths: paths, instanceID: original.id)
        let data = try JSONEncoder().encode(self)
        guard data.count <= 8_388_608 else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.sizeLimit) }
        try data.write(to: directory.appendingPathComponent("transaction.json"), options: .atomic)
    }
    func incoming(_ item: Item, paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath("incoming/\(item.area.rawValue)/\(item.name)", within: workspace(paths: paths))
    }
    func targetPaths(_ paths: LauncherPaths) -> LauncherPaths {
        var instance = original; instance.runDirectory = target
        if target == .custom { instance.customRunDirectory = targetCustomDirectory ?? original.customRunDirectory }
        return paths.including(instance)
    }
    func workspace(paths: LauncherPaths) throws -> URL {
        if stagingOnTarget == true {
            return try LauncherPaths.safePath(".directory-change-workspaces/\(id.uuidString)", within: targetPaths(paths).gameDataState(original.id))
        }
        return try Self.root(paths: paths, instanceID: original.id)
    }
    func destination(_ item: Item, paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath(item.name, within: item.area == .game ? paths.game(original.id) : paths.gameDataState(original.id))
    }
}

public enum RunDirectoryCopyGuard {
    /// Completed/cancelled workspaces remain discoverable after app restart.
    /// For a custom target the data may be on its volume, while the recovery
    /// record stays beside the originating instance's history.
    public static func preservedWorkspaces(paths: LauncherPaths, instanceID: UUID) -> [URL] {
        guard let parent = try? LauncherPaths.safePath("directory-change-recovery", within: paths.instance(instanceID)),
              let records = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return records.prefix(500).compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            if let record = try? RunDirectoryCopyJournal.load(paths: paths, instanceID: instanceID, recordDirectory: directory), record.stagingOnTarget == true,
               let workspace = try? record.workspace(paths: paths), FileManager.default.fileExists(atPath: workspace.path) { return workspace }
            return directory
        }.sorted { $0.path < $1.path }
    }
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
        return paths.runDirectory(for: instanceID) != .isolated && FileManager.default.fileExists(atPath: paths.gameDataState(instanceID).appendingPathComponent("directory-change.json").path)
    }
    public static func owner(paths: LauncherPaths, instanceID: UUID) throws -> RunDirectoryCopyOwner? {
        if FileManager.default.fileExists(atPath: paths.instance(instanceID).appendingPathComponent("run-directory-change").path) {
            return try RunDirectoryCopyJournal.load(paths: paths, instanceID: instanceID).owner
        }
        guard paths.runDirectory(for: instanceID) != .isolated else { return nil }
        return try sharedMarker(paths: paths, instanceID: instanceID)?.owner
    }
    static func requireAvailable(paths: LauncherPaths, instanceID: UUID, allowing id: UUID? = nil) throws {
        try InstanceCopyGuard.requireAvailable(paths: paths, instanceID: instanceID, allowing: id)
        if FileManager.default.fileExists(atPath: paths.instance(instanceID).appendingPathComponent("run-directory-change").path) {
            guard let id, try RunDirectoryCopyJournal.load(paths: paths, instanceID: instanceID).id == id else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.unfinishedCopy) }
        }
        try requireSharedAvailable(paths: paths, instanceID: instanceID, allowing: id)
    }
    static func requireSharedAvailable(paths: LauncherPaths, instanceID: UUID, allowing id: UUID? = nil) throws {
        guard paths.runDirectory(for: instanceID) != .isolated, let marker = try sharedMarker(paths: paths, instanceID: instanceID) else { return }
        guard marker.transactionID == id, marker.instanceID == instanceID else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.copyInProgress(marker.instanceName)) }
    }
    private static func sharedMarker(paths: LauncherPaths, instanceID: UUID) throws -> Marker? {
        let url = try markerURL(paths: paths, instanceID: instanceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let marker: Marker = try decode(url, limit: 8192)
        guard marker.version == 1, marker.instanceName.count <= 1024 else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidSharedCopyLock) }
        return marker
    }
    static func mark(_ journal: RunDirectoryCopyJournal, paths: LauncherPaths) throws {
        guard paths.runDirectory(for: journal.original.id) != .isolated else { return }
        let marker = Marker(version: 1, transactionID: journal.id, instanceID: journal.original.id, instanceName: journal.original.name)
        try JSONEncoder().encode(marker).write(to: markerURL(paths: paths, instanceID: journal.original.id), options: .atomic)
    }
    static func clear(_ journal: RunDirectoryCopyJournal, paths: LauncherPaths) throws {
        guard paths.runDirectory(for: journal.original.id) != .isolated, let marker = try sharedMarker(paths: paths, instanceID: journal.original.id) else { return }
        guard marker.transactionID == journal.id, marker.instanceID == journal.original.id else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.changedSharedCopyLock) }
        try FileManager.default.removeItem(at: markerURL(paths: paths, instanceID: journal.original.id))
    }
    static func decode<T: Decodable>(_ url: URL, limit: Int) throws -> T {
        try JSONDecoder().decode(T.self, from: read(url, limit: limit))
    }
    static func read(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.recordReadFailed(url.path)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= limit else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidRecordFile) }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.sizeLimit) }
        return data
    }
}
