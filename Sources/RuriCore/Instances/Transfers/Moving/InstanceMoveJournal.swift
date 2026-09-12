import RuriLocalization
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
        guard result.original.id == instanceID else { throw RuriError.message(Messages.CoreInstanceMoveJournal.moveRecordWrongInstance) }
        try result.validate(); return result
    }
    func validate() throws {
        var expected = original; expected.directoryID = targetCollection?.id ?? GameDirectory.defaultID; expected.lastInstanceMoveID = id
        if expected.runDirectory == .shared { expected.runDirectory = .isolated; expected.customRunDirectory = nil; expected.lastRunDirectoryChangeID = nil }
        guard version == 1, moved == expected, moved.frozenMemory == nil,
              (original.directoryID ?? GameDirectory.defaultID) == (sourceCollection?.id ?? GameDirectory.defaultID),
              (original.directoryID ?? GameDirectory.defaultID) != moved.directoryID,
              !original.name.isEmpty, original.name.count <= 1024, FileTreeManifest.validDigest(sourceDigest) else {
            throw RuriError.message(Messages.CoreInstanceMoveJournal.invalidMoveRecord)
        }
        if stagedIdentity != nil || publishedIdentity != nil || [.publishing, .committed, .retiring, .deleting].contains(phase) {
            guard destinationDigest != nil, workspaceIdentity != nil else { throw RuriError.message(Messages.CoreInstanceMoveJournal.missingDestinationVerification) }
        }
        if let destinationDigest, !FileTreeManifest.validDigest(destinationDigest) { throw RuriError.message(Messages.CoreInstanceMoveJournal.invalidDestinationDigest) }
        if [.retiring, .deleting].contains(phase), retirement == nil { throw RuriError.message(Messages.CoreInstanceMoveJournal.missingSourceRetirement) }
        for collection in [sourceCollection, targetCollection].compactMap({ $0 }) {
            guard collection.id != GameDirectory.defaultID, collection.url.isFileURL, collection.url.path.hasPrefix("/"), collection.bookmark == nil else { throw RuriError.message(Messages.CoreInstanceMoveJournal.invalidInstanceDirectory) }
        }
        for identity in [sourceIdentity, workspaceIdentity, stagedIdentity, publishedIdentity, retirement?.identity].compactMap({ $0 }) {
            guard identity.directory, identity.inode > 0, identity.volumeUUID.map({ !$0.isEmpty && $0.count <= 128 }) ?? true else { throw RuriError.message(Messages.CoreInstanceMoveJournal.invalidFileIdentity) }
        }
    }
    func validateLocations(paths: LauncherPaths) throws {
        for collection in [sourceCollection, targetCollection].compactMap({ $0 }) {
            guard paths.directories.contains(where: { $0.id == collection.id && $0.url.standardizedFileURL == collection.url.standardizedFileURL }) else {
                throw RuriError.message(Messages.CoreInstanceMoveJournal.changedMoveLocations)
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
        guard let instance = state.instances.first(where: { $0.id == original.id }) else { throw RuriError.message(Messages.CoreInstanceMoveJournal.removedMovingInstance) }
        if instance.lastInstanceMoveID != id {
            guard (instance.directoryID ?? GameDirectory.defaultID) == (original.directoryID ?? GameDirectory.defaultID) else { throw RuriError.message(Messages.CoreInstanceMoveJournal.changedInstanceLocation) }
            return false
        }
        guard instance.directoryID == moved.directoryID, instance.runDirectory == moved.runDirectory,
              instance.customRunDirectory == moved.customRunDirectory else { throw RuriError.message(Messages.CoreInstanceMoveJournal.mismatchedDirectoryBinding) }
        return true
    }
    func save(paths: LauncherPaths, at directory: URL? = nil) throws {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= 8_388_608 else { throw RuriError.message(Messages.CoreInstanceMoveJournal.moveRecordTooLarge) }
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
        guard !hasPending(paths: paths, instanceID: instanceID) else { throw RuriError.message(Messages.CoreInstanceMoveJournal.unfinishedMoveExists) }
    }
    static func requireDirectoryAvailable(_ id: UUID, paths: LauncherPaths) throws {
        let root = try LauncherPaths.safePath("instance-move-transactions", within: paths.root)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let records = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard records.count <= 500 else { throw RuriError.message(Messages.CoreInstanceMoveJournal.tooManyPendingMoves) }
        for record in records {
            guard let instanceID = UUID(uuidString: record.lastPathComponent) else { continue }
            if RepositoryMoveJournal.exists(paths: paths, instanceID: instanceID) {
                let journal = try RepositoryMoveJournal.load(paths: paths, instanceID: instanceID)
                guard (journal.original.directoryID ?? GameDirectory.defaultID) != id, journal.moved.directoryID != id else {
                    throw RuriError.message(Messages.CoreInstanceMoveJournal.unfinishedFolderMoves)
                }
                continue
            }
            let journal = try InstanceMoveJournal.load(paths: paths, instanceID: instanceID)
            guard (journal.original.directoryID ?? GameDirectory.defaultID) != id, journal.moved.directoryID != id else {
                throw RuriError.message(Messages.CoreInstanceMoveJournal.unfinishedFolderMoves)
            }
        }
    }
}
