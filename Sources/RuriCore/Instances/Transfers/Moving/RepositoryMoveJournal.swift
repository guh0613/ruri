import RuriLocalization
import Foundation
import Darwin

struct RepositoryMoveJournal: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case copying, publishing, committed, retiring, deleting, recovering }
    enum Part: String, Codable, CaseIterable, Sendable { case metadata, version }
    struct FileSet: Codable, Sendable {
        let part: Part
        var identity: RunDirectoryCopyJournal.Identity
        var digest: String
    }
    struct Publication: Codable, Sendable {
        let part: Part
        let staged: RunDirectoryCopyJournal.Identity
        var published: RunDirectoryCopyJournal.Identity?
        let digest: String
    }
    struct Resource: Codable, Sendable {
        let path: String
        let sha1: String
        let size: Int64
    }
    var version = 1
    let id: UUID
    let original: GameInstance
    let moved: GameInstance
    let sourceCollection: GameDirectory?
    let targetCollection: GameDirectory?
    let sources: [FileSet]
    var phase = Phase.copying
    var workspaceIdentity: RunDirectoryCopyJournal.Identity?
    var publications: [Publication] = []
    var resources: [Resource] = []
    var retirementIdentity: RunDirectoryCopyJournal.Identity?

    static func exists(paths: LauncherPaths, instanceID: UUID, at root: URL? = nil) -> Bool {
        guard let file = try? (root ?? InstanceMoveJournal.root(paths: paths, instanceID: instanceID)).appendingPathComponent("repository.json") else { return false }
        return FileManager.default.fileExists(atPath: file.path)
    }
    static func load(paths: LauncherPaths, instanceID: UUID, at root: URL? = nil) throws -> Self {
        let file = try (root ?? InstanceMoveJournal.root(paths: paths, instanceID: instanceID)).appendingPathComponent("repository.json")
        let record: Self = try RunDirectoryCopyGuard.decode(file, limit: 32 * 1024 * 1024)
        guard record.version == 1, record.original.id == instanceID, record.moved.id == instanceID,
              record.original.directoryID != record.moved.directoryID, record.moved.lastInstanceMoveID == record.id,
              (record.sourceCollection?.id ?? GameDirectory.defaultID) == (record.original.directoryID ?? GameDirectory.defaultID),
              (record.targetCollection?.id ?? GameDirectory.defaultID) == record.moved.directoryID,
              record.original.repositoryVersionID != nil || record.targetCollection?.isMinecraft == true,
              (record.moved.repositoryVersionID != nil) == (record.targetCollection?.isMinecraft == true),
              record.moved.installed, record.sources.map(\.part) == (record.original.repositoryVersionID == nil ? [.metadata] : [.metadata, .version]),
              record.sources.allSatisfy({ FileTreeManifest.validDigest($0.digest) }),
              Set(record.publications.map(\.part)).count == record.publications.count,
              record.publications.allSatisfy({ FileTreeManifest.validDigest($0.digest) }), record.resources.count <= 150_000 else {
            throw RuriError.message(Messages.CoreRepositoryMoveJournal.recordText1)
        }
        for name in [record.original.repositoryVersionID, record.moved.repositoryVersionID].compactMap({ $0 }) { try MinecraftDirectoryScan.checkIdentifier(name) }
        try InstanceTransfer.validate(record.moved)
        return record
    }
    func save(paths: LauncherPaths, at root: URL? = nil) throws {
        let directory = try root ?? InstanceMoveJournal.root(paths: paths, instanceID: original.id)
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("repository.json"), options: .atomic)
    }
    func source(_ part: Part, paths: LauncherPaths) throws -> URL { try location(part, instance: original, collection: sourceCollection, paths: paths) }
    func destination(_ part: Part, paths: LauncherPaths) throws -> URL { try location(part, instance: moved, collection: targetCollection, paths: paths) }
    private func location(_ part: Part, instance: GameInstance, collection: GameDirectory?, paths: LauncherPaths) throws -> URL {
        let relative: String
        switch part {
        case .metadata: relative = (collection?.isMinecraft == true ? ".ruri/instances/" : "instances/") + instance.id.uuidString
        case .version:
            guard let name = instance.repositoryVersionID else { throw RuriError.message(Messages.CoreRepositoryMoveJournal.nameText1) }
            relative = "versions/" + name
        }
        return try LauncherPaths.safePath(relative, within: collection?.url ?? paths.root)
    }
    func workspace(paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath(targetCollection?.isMinecraft == true ? ".ruri/moves/" + id.uuidString : "instances/.ruri-instance-move-" + id.uuidString,
                                   within: targetCollection?.url ?? paths.root)
    }
    func incoming(_ part: Part, paths: LauncherPaths) throws -> URL { try workspace(paths: paths).appendingPathComponent(part.rawValue) }
    func retirement(paths: LauncherPaths) throws -> URL {
        try LauncherPaths.safePath(sourceCollection?.isMinecraft == true ? ".ruri/move-retired/" + id.uuidString : "instances/.ruri-move-retired-" + id.uuidString,
                                   within: sourceCollection?.url ?? paths.root)
    }
    func isCommitted(_ state: PersistentState) throws -> Bool {
        guard let instance = state.instances.first(where: { $0.id == original.id }) else { throw RuriError.message(Messages.CoreRepositoryMoveJournal.instanceText1) }
        if instance.lastInstanceMoveID != id {
            guard instance.directoryID == original.directoryID else { throw RuriError.message(Messages.CoreRepositoryMoveJournal.instanceText2) }; return false
        }
        guard instance.directoryID == moved.directoryID, instance.repositoryVersionID == moved.repositoryVersionID,
              instance.runDirectory == moved.runDirectory, instance.customRunDirectory == moved.customRunDirectory else { throw RuriError.message(Messages.CoreRepositoryMoveJournal.instanceText3) }
        return true
    }
    func validateLocations(paths: LauncherPaths) throws {
        let state = try StateStore.load(paths)
        for directory in [sourceCollection, targetCollection].compactMap({ $0 }) {
            guard state.gameDirectories?.contains(where: { $0.id == directory.id && $0.url.standardizedFileURL == directory.url.standardizedFileURL && $0.isMinecraft == directory.isMinecraft }) == true else {
                throw RuriError.message(Messages.CoreRepositoryMoveJournal.stateText1)
            }
            try directory.validateAvailability()
        }
        if let custom = original.customRunDirectory { try custom.validateAvailability() }
    }
    func reserveVersions() throws {
        for (directory, version) in [(sourceCollection, original.repositoryVersionID), (targetCollection, moved.repositoryVersionID)] {
            guard let directory, let version else { continue }
            let folder = try LauncherPaths.safePath(".ruri/moves/" + id.uuidString, within: directory.url)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let record = RepositoryMoveReservation(id: id, instanceID: original.id, version: version)
            try JSONEncoder().encode(record).write(to: folder.appendingPathComponent("reservation.json"), options: .withoutOverwriting)
        }
    }
    func clearReservations() throws {
        for (directory, version) in [(sourceCollection, original.repositoryVersionID), (targetCollection, moved.repositoryVersionID)] {
            guard let directory, let version else { continue }
            let folder = try LauncherPaths.safePath(".ruri/moves/" + id.uuidString, within: directory.url)
            let file = folder.appendingPathComponent("reservation.json")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let current: RepositoryMoveReservation = try RunDirectoryCopyGuard.decode(file, limit: 8192)
            guard current == .init(id: id, instanceID: original.id, version: version) else { throw RuriError.message(Messages.CoreRepositoryMoveJournal.currentText1) }
            try FileManager.default.removeItem(at: file)
            _ = rmdir(folder.path)
        }
    }
}

struct RepositoryMoveReservation: Codable, Equatable {
    let id: UUID
    let instanceID: UUID
    let version: String
    static func names(in repository: URL) throws -> Set<String> {
        let root = try LauncherPaths.safePath(".ruri/moves", within: repository)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var names = Set<String>()
        for folder in try FileTree.children(in: root) where UUID(uuidString: folder.lastPathComponent) != nil {
            let file = try LauncherPaths.safePath("reservation.json", within: folder)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let record: Self = try RunDirectoryCopyGuard.decode(file, limit: 8192)
            guard record.id.uuidString == folder.lastPathComponent else { throw RuriError.message(Messages.CoreRepositoryMoveJournal.recordText2) }
            try MinecraftDirectoryScan.checkIdentifier(record.version)
            names.insert(MinecraftGameDataFiles.key(record.version))
        }
        return names
    }
}
