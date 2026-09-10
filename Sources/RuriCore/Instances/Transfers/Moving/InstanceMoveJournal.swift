import Foundation

struct InstanceMoveJournal: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case copying, publishing, committed, retiring, deleting, recovering }
    struct Retirement: Codable, Sendable {
        let token: UUID
        let identity: RunDirectoryCopyJournal.Identity
    }
    var version = 1
    let id: UUID
    let original: GameInstance
    let moved: GameInstance
    let sourceCollection: GameDirectory?
    let targetCollection: GameDirectory?
    let createdAt: Date
    let sourceIdentity: RunDirectoryCopyJournal.Identity
    let sourceDigest: String
    var phase: Phase = .copying
    var workspaceIdentity: RunDirectoryCopyJournal.Identity?
    var stagedIdentity: RunDirectoryCopyJournal.Identity?
    var publishedIdentity: RunDirectoryCopyJournal.Identity?
    var destinationDigest: String?
    var retirement: Retirement?

    static func root(paths: LauncherPaths, instanceID: UUID) throws -> URL {
        try LauncherPaths.safePath("instance-move-transactions/\(instanceID.uuidString)", within: paths.root)
    }
    static func load(paths: LauncherPaths, instanceID: UUID, at parent: URL? = nil) throws -> Self {
        let root = try parent ?? Self.root(paths: paths, instanceID: instanceID)
        let result: Self = try RunDirectoryCopyGuard.decode(root.appendingPathComponent("transaction.json"), limit: 8_388_608)
        guard result.original.id == instanceID else { throw RuriError.message("移动记录不属于所选实例。") }
        try result.validate(); return result
    }
    func validate() throws {
        var expected = original; expected.directoryID = targetCollection?.id ?? GameDirectory.defaultID; expected.lastInstanceMoveID = id
        if expected.runDirectory == .shared { expected.runDirectory = .isolated; expected.customRunDirectory = nil; expected.lastRunDirectoryChangeID = nil }
        guard version == 1, moved == expected, moved.frozenMemory == nil,
              (original.directoryID ?? GameDirectory.defaultID) == (sourceCollection?.id ?? GameDirectory.defaultID),
              (original.directoryID ?? GameDirectory.defaultID) != moved.directoryID,
              !original.name.isEmpty, original.name.count <= 1024, FileTreeManifest.validDigest(sourceDigest) else {
            throw RuriError.message("实例移动记录无效，原文件和工作副本已保留。")
        }
        if stagedIdentity != nil || publishedIdentity != nil || [.publishing, .committed, .retiring, .deleting].contains(phase) {
            guard destinationDigest != nil, workspaceIdentity != nil else { throw RuriError.message("移动记录缺少目标校验信息。") }
        }
        if let destinationDigest, !FileTreeManifest.validDigest(destinationDigest) { throw RuriError.message("移动目标的校验摘要无效。") }
        if [.retiring, .deleting].contains(phase), retirement == nil { throw RuriError.message("移动记录缺少来源退役信息。") }
        for collection in [sourceCollection, targetCollection].compactMap({ $0 }) {
            guard collection.id != GameDirectory.defaultID, collection.url.isFileURL, collection.url.path.hasPrefix("/"), collection.bookmark == nil else { throw RuriError.message("移动记录中的实例文件夹无效。") }
        }
        for identity in [sourceIdentity, workspaceIdentity, stagedIdentity, publishedIdentity, retirement?.identity].compactMap({ $0 }) {
            guard identity.directory, identity.inode > 0, identity.volumeUUID.map({ !$0.isEmpty && $0.count <= 128 }) ?? true else { throw RuriError.message("移动记录中的文件身份无效。") }
        }
    }
    func validateLocations(paths: LauncherPaths) throws {
        for collection in [sourceCollection, targetCollection].compactMap({ $0 }) {
            guard paths.directories.contains(where: { $0.id == collection.id && $0.url.standardizedFileURL == collection.url.standardizedFileURL }) else {
                throw RuriError.message("移动涉及的实例文件夹位置已改变，请恢复原位置后继续。")
            }
            try collection.validateAvailability()
        }
        _ = try source(paths: paths); _ = try destination(paths: paths)
    }
    func source(paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath("instances/\(original.id.uuidString)", within: sourceCollection?.url ?? paths.root)
    }
    func destination(paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath("instances/\(moved.id.uuidString)", within: targetCollection?.url ?? paths.root)
    }
    func workspace(paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath("instances/.ruri-instance-move-\(id.uuidString)", within: targetCollection?.url ?? paths.root)
    }
    func incoming(paths: LauncherPaths) throws -> URL { try workspace(paths: paths).appendingPathComponent("instance") }
    func retirementParent(paths: LauncherPaths) throws -> URL? {
        guard let retirement else { return nil }
        return try LauncherPaths.safePath("instances/.ruri-instance-move-source-\(id.uuidString)-\(retirement.token.uuidString)", within: sourceCollection?.url ?? paths.root)
    }
    func retiredSource(paths: LauncherPaths) throws -> URL? { try retirementParent(paths: paths)?.appendingPathComponent("instance") }
    func isCommitted(in state: PersistentState) throws -> Bool {
        guard let instance = state.instances.first(where: { $0.id == original.id }) else { throw RuriError.message("移动中的实例已被移除，文件已保留。") }
        if instance.lastInstanceMoveID != id {
            guard (instance.directoryID ?? GameDirectory.defaultID) == (original.directoryID ?? GameDirectory.defaultID) else { throw RuriError.message("实例位置与移动记录不一致，文件已保留。") }
            return false
        }
        guard instance.directoryID == moved.directoryID, instance.runDirectory == moved.runDirectory,
              instance.customRunDirectory == moved.customRunDirectory else { throw RuriError.message("实例的移动凭据与目录绑定不一致。") }
        return true
    }
    func save(paths: LauncherPaths, at directory: URL? = nil) throws {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 8_388_608 else { throw RuriError.message("实例移动记录过大。") }
        let root = try directory ?? Self.root(paths: paths, instanceID: original.id)
        try data.write(to: root.appendingPathComponent("transaction.json"), options: .atomic)
    }
}

public enum InstanceMoveGuard {
    public static func preservedWorkspaces(paths: LauncherPaths, instanceID: UUID) -> [URL] {
        guard let parent = try? LauncherPaths.safePath("instance-move-recovery", within: paths.root),
              let entries = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return [] }
        let current = (try? StateStore.load(paths)).map { paths.configured(with: $0).instance(instanceID).standardizedFileURL.path }
        return entries.filter { $0.lastPathComponent.hasPrefix(instanceID.uuidString + "-") }.prefix(500).flatMap { entry -> [URL] in
            if let record = try? RepositoryMoveJournal.load(paths: paths, instanceID: instanceID, at: entry) {
                return [entry, try? record.retirement(paths: paths)].compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            guard let record = try? InstanceMoveJournal.load(paths: paths, instanceID: instanceID, at: entry) else { return [entry] }
            var candidates = [try? record.workspace(paths: paths), try? record.retirementParent(paths: paths)].compactMap { $0 }
            if record.phase != .recovering, let source = try? record.source(paths: paths), source.standardizedFileURL.path != current { candidates.append(source) }
            let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
            return existing.isEmpty ? [entry] : existing
        }.sorted { $0.path < $1.path }
    }
    public static func hasPending(paths: LauncherPaths, instanceID: UUID) -> Bool {
        guard let root = try? InstanceMoveJournal.root(paths: paths, instanceID: instanceID) else { return true }
        return FileManager.default.fileExists(atPath: root.path)
    }
    static func requireAvailable(paths: LauncherPaths, instanceID: UUID) throws {
        guard !hasPending(paths: paths, instanceID: instanceID) else { throw RuriError.message("此实例有未完成的移动，请先恢复实例移动。") }
    }
    static func requireDirectoryAvailable(_ id: UUID, paths: LauncherPaths) throws {
        let root = try LauncherPaths.safePath("instance-move-transactions", within: paths.root)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let records = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard records.count <= 500 else { throw RuriError.message("待处理的实例移动过多，请先恢复。") }
        for record in records {
            guard let instanceID = UUID(uuidString: record.lastPathComponent) else { continue }
            if RepositoryMoveJournal.exists(paths: paths, instanceID: instanceID) {
                let journal = try RepositoryMoveJournal.load(paths: paths, instanceID: instanceID)
                guard (journal.original.directoryID ?? GameDirectory.defaultID) != id, journal.moved.directoryID != id else {
                    throw RuriError.message("此文件夹还有未完成的实例移动，请先恢复原位置并处理移动。")
                }
                continue
            }
            let journal = try InstanceMoveJournal.load(paths: paths, instanceID: instanceID)
            guard (journal.original.directoryID ?? GameDirectory.defaultID) != id, journal.moved.directoryID != id else {
                throw RuriError.message("此文件夹还有未完成的实例移动，请先恢复原位置并处理移动。")
            }
        }
    }
}
