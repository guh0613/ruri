import Foundation
import Darwin

public struct InstanceCopyOwner: Codable, Sendable {
    public let transactionID: UUID
    public let sourceID: UUID
    public let copyID: UUID
    public let sourceName: String
    public let copyName: String
}

struct InstanceCopyJournal: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case copying, publishing, committed, recovering }
    var version = 1
    let id: UUID
    let original: GameInstance
    let copy: GameInstance
    let targetCollection: GameDirectory?
    let createdAt: Date
    var phase: Phase
    var stagedIdentity: RunDirectoryCopyJournal.Identity?
    var publishedIdentity: RunDirectoryCopyJournal.Identity?
    var owner: InstanceCopyOwner { .init(transactionID: id, sourceID: original.id, copyID: copy.id, sourceName: original.name, copyName: copy.name) }
    static func root(paths: LauncherPaths, sourceID: UUID) throws -> URL {
        try LauncherPaths.safePath("instance-copy-transactions/\(sourceID.uuidString)", within: paths.root)
    }
    static func load(paths: LauncherPaths, sourceID: UUID, at directory: URL? = nil) throws -> Self {
        let parent = try directory ?? root(paths: paths, sourceID: sourceID)
        let record: Self = try RunDirectoryCopyGuard.decode(parent.appendingPathComponent("transaction.json"), limit: 8_388_608)
        guard record.version == 1, record.original.id == sourceID, record.copy.id != sourceID,
              record.copy.runDirectory == .isolated, record.copy.customRunDirectory == nil,
              record.copy.lastInstanceCopyID == record.id, record.copy.frozenMemory == nil,
              record.copy.directoryID == (record.targetCollection?.id ?? GameDirectory.defaultID),
              !record.copy.name.isEmpty, record.copy.name.count <= 256, record.original.name.count <= 1024 else { throw RuriError.message("实例复制记录无效，工作副本已保留。") }
        if let collection = record.targetCollection {
            guard collection.id != GameDirectory.defaultID, collection.url.isFileURL, collection.url.path.hasPrefix("/"), (collection.bookmark?.count ?? 0) <= 1_048_576 else { throw RuriError.message("复制目标的文件夹记录无效。") }
        }
        for identity in [record.stagedIdentity, record.publishedIdentity].compactMap({ $0 }) {
            guard identity.directory, identity.inode > 0, identity.volumeUUID.map({ !$0.isEmpty && $0.count <= 128 }) ?? true else { throw RuriError.message("实例副本的文件身份记录无效。") }
        }
        return record
    }
    func validateTarget(paths: LauncherPaths) throws {
        if let targetCollection {
            guard let registered = paths.directories.first(where: { $0.id == targetCollection.id }),
                  registered.url.standardizedFileURL.path == targetCollection.url.standardizedFileURL.path else { throw RuriError.message("目标实例文件夹的登记位置已经变化，请恢复原位置后处理复制。") }
            try targetCollection.validateAvailability()
        }
        try paths.including(copy).validateInstanceLocation(copy.id)
    }
    func workspace(paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath("instances/.ruri-instance-copy-\(id.uuidString)", within: targetCollection?.url ?? paths.root)
    }
    func incoming(paths: LauncherPaths) throws -> URL { try workspace(paths: paths).appendingPathComponent("instance") }
    func destination(paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath("instances/\(copy.id.uuidString)", within: targetCollection?.url ?? paths.root)
    }
    func save(paths: LauncherPaths, at directory: URL? = nil) throws {
        let parent = try directory ?? Self.root(paths: paths, sourceID: original.id)
        let data = try JSONEncoder().encode(self)
        guard data.count <= 8_388_608 else { throw RuriError.message("实例复制记录超过大小限制。") }
        try data.write(to: parent.appendingPathComponent("transaction.json"), options: .atomic)
    }
}

public enum InstanceCopyGuard {
    static let markerName = ".ruri-instance-copy.json"
    public static func hasPending(paths: LauncherPaths, instanceID: UUID) -> Bool {
        guard let record = try? InstanceCopyJournal.root(paths: paths, sourceID: instanceID) else { return true }
        return FileManager.default.fileExists(atPath: record.path) || FileManager.default.fileExists(atPath: paths.instance(instanceID).appendingPathComponent(markerName).path)
    }
    public static func owner(paths: LauncherPaths, instanceID: UUID) throws -> InstanceCopyOwner? {
        let own = try InstanceCopyJournal.root(paths: paths, sourceID: instanceID)
        if FileManager.default.fileExists(atPath: own.path) { return try InstanceCopyJournal.load(paths: paths, sourceID: instanceID).owner }
        let marker = try LauncherPaths.safePath(markerName, within: paths.instance(instanceID))
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let owner: InstanceCopyOwner = try RunDirectoryCopyGuard.decode(marker, limit: 8192)
        guard owner.copyID == instanceID, owner.copyID != owner.sourceID, owner.sourceName.count <= 1024, owner.copyName.count <= 256 else { throw RuriError.message("实例复制占用信息无效。") }
        return owner
    }
    static func requireAvailable(paths: LauncherPaths, instanceID: UUID, allowing id: UUID?) throws {
        guard let owner = try owner(paths: paths, instanceID: instanceID) else { return }
        guard owner.transactionID == id else { throw RuriError.message("“\(owner.sourceName)”有未完成的实例复制，请先在实例菜单中恢复复制。") }
    }
    static func mark(_ journal: InstanceCopyJournal, at directory: URL) throws {
        try JSONEncoder().encode(journal.owner).write(to: directory.appendingPathComponent(markerName), options: .withoutOverwriting)
    }
    static func clear(_ journal: InstanceCopyJournal, at directory: URL) throws {
        let file = try LauncherPaths.safePath(markerName, within: directory)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let marker: InstanceCopyOwner = try RunDirectoryCopyGuard.decode(file, limit: 8192)
        guard marker.transactionID == journal.id, marker.sourceID == journal.original.id, marker.copyID == journal.copy.id else { throw RuriError.message("副本占用记录已经改变，未清除其他操作的记录。") }
        try FileManager.default.removeItem(at: file)
    }
    static func requireDirectoryAvailable(_ id: UUID, paths: LauncherPaths) throws {
        let root = try LauncherPaths.safePath("instance-copy-transactions", within: paths.root)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let records = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard records.count <= 500 else { throw RuriError.message("待处理的实例复制过多，请先恢复后再调整文件夹。") }
        for directory in records {
            guard let source = UUID(uuidString: directory.lastPathComponent) else { continue }
            let journal = try InstanceCopyJournal.load(paths: paths, sourceID: source)
            guard journal.original.directoryID != id, journal.copy.directoryID != id else { throw RuriError.message("此文件夹还有未完成的实例复制，请恢复原路径并处理后再重新定位。") }
        }
    }
    public static func preservedWorkspaces(paths: LauncherPaths, sourceID: UUID) -> [URL] {
        guard let parent = try? LauncherPaths.safePath("instance-copy-recovery", within: paths.root),
              let entries = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { $0.lastPathComponent.hasPrefix(sourceID.uuidString + "-") }.prefix(500).map { directory in
            if let journal = try? InstanceCopyJournal.load(paths: paths, sourceID: sourceID, at: directory),
               let workspace = try? journal.workspace(paths: paths), FileManager.default.fileExists(atPath: workspace.path) { return workspace }
            return directory
        }.sorted { $0.path < $1.path }
    }
}
