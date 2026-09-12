import RuriLocalization
import Foundation
import Darwin
import CryptoKit

public struct RepositoryImportRecovery: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let workspace: URL
    public let canFinish: Bool
    public let registered: Bool
    public var copySource: InstanceCopyOwner? = nil
}

public struct RepositoryImportFailure: LocalizedError, Sendable {
    public let message: String
    public let preservedFiles: URL?
    public var errorDescription: String? { message }
}

struct RepositoryImportJournal: Codable, Equatable {
    enum Phase: String, Codable { case installing, publishing, published }
    var schema = 1
    var instance: GameInstance
    let directory: GameDirectory
    var phase = Phase.installing
    var stagedMetadata: RunDirectoryCopyJournal.Identity?
    var stagedVersion: RunDirectoryCopyJournal.Identity?
    var publishedMetadata: RunDirectoryCopyJournal.Identity?
    var publishedVersion: RunDirectoryCopyJournal.Identity?
    var manifestDigest: String?
    var copySource: InstanceCopyOwner?
    var metadataIdentity: RunDirectoryCopyJournal.Identity? { publishedMetadata ?? stagedMetadata }
    var versionIdentity: RunDirectoryCopyJournal.Identity? { publishedVersion ?? stagedVersion }
}

/// Downloads use the selected repository's resource cache; the version and
/// launcher metadata stay private until both can be published without replacing
/// existing files. A journal bridges publication and the state transaction.
final class RepositoryImportTransaction {
    static let markerName = ".ruri-import.json"
    let paths: LauncherPaths
    let staging: LauncherPaths
    let workspace: URL
    private var journal: RepositoryImportJournal
    private let operation = GameDataOperationLock()
    private let nameLock = GameDataOperationLock()

    init(instance: GameInstance, paths: LauncherPaths, copySource: InstanceCopyOwner? = nil) throws {
        self.paths = paths.including(instance)
        staging = paths.stagingRepositoryImport(instance)
        workspace = staging.repositoryImportWorkspace(instance.id)
        guard let directory = paths.directories.first(where: { $0.id == instance.directoryID }), directory.isMinecraft else {
            throw RuriError.message(Messages.CoreRepositoryImport.directoryText1)
        }
        journal = .init(instance: instance, directory: directory, copySource: copySource)
        try Self.validateDirectory(directory, paths: paths)
        try Self.lockName(instance.repositoryVersionID ?? "", directory: directory, lock: nameLock)
        try RepositoryImportStore.requireNameAvailable(instance.repositoryVersionID ?? "", directory: directory, paths: paths)
        // Older launchers must stop before a journal they cannot recover appears.
        try StateStore.update(paths) { _ in try Self.validateDirectory(directory, paths: paths) }
        try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard mkdir(workspace.path, S_IRWXU) == 0 else { throw RuriError.message(Messages.CoreRepositoryImport.directoryText2) }
        do {
            try operation.acquire(directory: workspace, name: ".operation.lock")
            try save()
        } catch { try? FileManager.default.removeItem(at: workspace); throw error }
    }

    private init(journal: RepositoryImportJournal, paths: LauncherPaths) throws {
        self.journal = journal; self.paths = paths.including(journal.instance)
        staging = paths.stagingRepositoryImport(journal.instance)
        workspace = staging.repositoryImportWorkspace(journal.instance.id)
        try Self.validateDirectory(journal.directory, paths: paths)
        try Self.lockName(journal.instance.repositoryVersionID ?? "", directory: journal.directory, lock: nameLock)
        try operation.acquire(directory: workspace, name: ".operation.lock")
        let current = try Self.read(workspace, directory: journal.directory)
        guard current == journal else { throw RuriError.message(Messages.CoreRepositoryImport.currentText1) }
    }

    func publish(_ instance: GameInstance) throws -> GameInstance {
        try publishFiles(instance)
        try Task.checkCancellation()
        return try finish()
    }

    func publishFiles(_ instance: GameInstance) throws {
        guard instance.id == journal.instance.id, instance.directoryID == journal.directory.id,
              instance.repositoryVersionID == journal.instance.repositoryVersionID, instance.runDirectory == .isolated, instance.installed else {
            throw RuriError.message(Messages.CoreRepositoryImport.publishFilesText1)
        }
        try Self.validateDirectory(journal.directory, paths: paths)
        journal.instance = instance
        journal.manifestDigest = try Self.digest(staging.manifest(instance.id))
        let marker = try JSONEncoder().encode(instance.id)
        for folder in [staging.instance(instance.id), staging.versionDirectory(instance.id)] {
            try marker.write(to: folder.appendingPathComponent(Self.markerName), options: .withoutOverwriting)
        }
        journal.stagedMetadata = try .read(staging.instance(instance.id))
        journal.stagedVersion = try .read(staging.versionDirectory(instance.id))
        journal.phase = .publishing; try save()
        try FileManager.default.createDirectory(at: paths.instance(instance.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.versionDirectory(instance.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Task.checkCancellation()
        try RunDirectoryFileCopy.publish(staging.instance(instance.id), to: paths.instance(instance.id), directory: true, ignoringTransientFiles: false) { identity in
            journal.publishedMetadata = identity; try save()
        } validate: { try Self.validateDirectory(journal.directory, paths: paths) } progress: { _ in }
        try Task.checkCancellation()
        try RunDirectoryFileCopy.publish(staging.versionDirectory(instance.id), to: paths.versionDirectory(instance.id), directory: true, ignoringTransientFiles: false) { identity in
            journal.publishedVersion = identity; try save()
        } validate: { try Self.validateDirectory(journal.directory, paths: paths) } progress: { _ in }
        journal.phase = .published; try save()
    }

    private func finish() throws -> GameInstance {
        let instance = journal.instance
        try validatePublication()
        _ = try StateStore.update(paths) { state in
            try Self.validateDirectory(journal.directory, paths: paths)
            if let existing = state.instances.first(where: { $0.id == instance.id }) {
                guard existing.directoryID == instance.directoryID, existing.repositoryVersionID == instance.repositoryVersionID else {
                    throw RuriError.message(Messages.CoreRepositoryImport.existingText1)
                }
            } else {
                guard !state.instances.contains(where: {
                    $0.directoryID == instance.directoryID && $0.repositoryVersionID?.localizedCaseInsensitiveCompare(instance.repositoryVersionID ?? "") == .orderedSame
                }) else { throw RuriError.message(Messages.CoreRepositoryImport.existingText2) }
                state.instances.append(instance)
            }
            state.selectedDirectoryID = instance.directoryID; state.selectedInstanceID = instance.id
        }
        // State already owns the exact UUID before discovery can see this folder.
        do {
            try clearMarker(paths.versionDirectory(instance.id))
            try clearMarker(paths.instance(instance.id))
            let retired = try retireWorkspace(category: "import-completed")
            try? FileManager.default.removeItem(at: retired.deletingLastPathComponent())
        } catch { /* The published journal remains available for cleanup. */ }
        return instance
    }

    func preserve() throws -> URL {
        try Self.validateDirectory(journal.directory, paths: paths)
        let instance = journal.instance
        guard !(try StateStore.load(paths)).instances.contains(where: { $0.id == instance.id }) else {
            throw RuriError.message(Messages.CoreRepositoryImport.instanceText1)
        }
        for (folder, source, original, published) in [
            (paths.versionDirectory(instance.id), staging.versionDirectory(instance.id), journal.stagedVersion, journal.publishedVersion),
            (paths.instance(instance.id), staging.instance(instance.id), journal.stagedMetadata, journal.publishedMetadata)
        ] {
            let identity = published ?? original
            guard let identity, FileManager.default.fileExists(atPath: folder.path) else { continue }
            if published == nil, original?.matches(source) == true, !identity.matches(folder) { continue }
            guard identity.matches(folder) else { throw RuriError.message(Messages.CoreRepositoryImport.identityText1(String(describing: folder.path))) }
            try RunDirectoryFileCopy.returnToWorkspace(folder, workspace: workspace)
        }
        return try retireWorkspace(category: "import-recovery")
    }

    private func retireWorkspace(category: String) throws -> URL {
        let parent = try LauncherPaths.safePath(".ruri/\(category)", within: journal.directory.url)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let kept = parent.appendingPathComponent(UUID().uuidString)
        guard mkdir(kept.path, S_IRWXU) == 0 else { throw RuriError.message(Messages.CoreRepositoryImport.keptText1) }
        let destination = kept.appendingPathComponent("files")
        guard rename(workspace.path, destination.path) == 0 else { throw RuriError.message(Messages.CoreRepositoryImport.destinationText1) }
        return destination
    }

    private func validatePublication() throws {
        let registered = try StateStore.load(paths).instances.contains {
            $0.id == journal.instance.id && $0.directoryID == journal.instance.directoryID && $0.repositoryVersionID == journal.instance.repositoryVersionID
        }
        let manifestMatches = registered ? true : try Self.digest(paths.manifest(journal.instance.id)) == journal.manifestDigest
        guard journal.phase == .published, journal.instance.installed,
              journal.versionIdentity?.matches(paths.versionDirectory(journal.instance.id)) == true,
              journal.metadataIdentity?.matches(paths.instance(journal.instance.id)) == true,
              manifestMatches else {
            throw RuriError.message(Messages.CoreRepositoryImport.manifestMatchesText1)
        }
        try Self.validateDirectory(journal.directory, paths: paths)
    }
    private func clearMarker(_ folder: URL) throws {
        let marker = try LauncherPaths.safePath(Self.markerName, within: folder)
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let id: UUID = try RunDirectoryCopyGuard.decode(marker, limit: 1024)
        guard id == journal.instance.id else { throw RuriError.message(Messages.CoreRepositoryImport.idText1) }
        try FileManager.default.removeItem(at: marker)
    }
    private func save() throws { try JSONEncoder().encode(journal).write(to: workspace.appendingPathComponent("transaction.json"), options: .atomic) }
    private static func digest(_ file: URL) throws -> String {
        SHA256.hash(data: try RunDirectoryCopyGuard.read(file, limit: 8_388_608)).map { String(format: "%02x", $0) }.joined()
    }
    private static func lockName(_ name: String, directory: GameDirectory, lock: GameDataOperationLock) throws {
        let key = SHA256.hash(data: Data(name.precomposedStringWithCanonicalMapping.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        let root = try LauncherPaths.safePath(".ruri/import-locks", within: directory.url)
        try lock.acquire(directory: root, name: key + ".lock")
    }
    private static func validateDirectory(_ directory: GameDirectory, paths: LauncherPaths) throws {
        let current = try StateStore.load(paths)
        guard let actual = current.gameDirectories?.first(where: { $0.id == directory.id }),
              actual.url.standardizedFileURL.path == directory.url.standardizedFileURL.path, actual.isMinecraft else {
            throw RuriError.message(Messages.CoreRepositoryImport.actualText1)
        }
        try directory.validateAvailability()
    }
    static func read(_ workspace: URL, directory: GameDirectory) throws -> RepositoryImportJournal {
        let record: RepositoryImportJournal = try RunDirectoryCopyGuard.decode(LauncherPaths.safePath("transaction.json", within: workspace), limit: 2_097_152)
        guard record.schema == 1, record.instance.id.uuidString == workspace.lastPathComponent,
              record.directory.id == directory.id, record.directory.isMinecraft,
              record.directory.url.standardizedFileURL.path == directory.url.standardizedFileURL.path,
              record.instance.directoryID == directory.id, let version = record.instance.repositoryVersionID,
              record.instance.runDirectory == .isolated, record.instance.importedInstallation == nil else { throw RuriError.message(Messages.CoreRepositoryImport.versionText1(String(describing: workspace.path))) }
        try MinecraftDirectoryScan.checkIdentifier(version)
        try InstanceTransfer.validate(record.instance)
        if let owner = record.copySource {
            guard owner.copyID == record.instance.id, owner.transactionID == record.instance.lastInstanceCopyID,
                  owner.sourceID != owner.copyID, owner.sourceName.count <= 1024, owner.copyName == record.instance.name else {
                throw RuriError.message(Messages.CoreRepositoryImport.ownerText1)
            }
        }
        return record
    }
    static func recover(_ recovery: RepositoryImportRecovery, directory: GameDirectory, paths: LauncherPaths, finish: Bool) throws -> URL? {
        let journal = try read(recovery.workspace, directory: directory)
        let transaction = try Self(journal: journal, paths: paths)
        if finish { _ = try transaction.finish(); return nil }
        return try transaction.preserve()
    }
}

public enum RepositoryImportStore {
    static func reservedVersionNames(in repository: URL) throws -> Set<String> {
        let root = try LauncherPaths.safePath(".ruri/imports", within: repository)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var names = Set<String>()
        for workspace in try FileTree.children(in: root) where UUID(uuidString: workspace.lastPathComponent) != nil {
            let file = try LauncherPaths.safePath("transaction.json", within: workspace)
            // A brand-new workspace contains no version files before its first journal.
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let journal: RepositoryImportJournal = try RunDirectoryCopyGuard.decode(file, limit: 2_097_152)
            guard journal.schema == 1, journal.instance.id.uuidString == workspace.lastPathComponent,
                  journal.directory.url.standardizedFileURL.path == repository.standardizedFileURL.path,
                  journal.instance.directoryID == journal.directory.id,
                  let name = journal.instance.repositoryVersionID else { throw RuriError.message(Messages.CoreRepositoryImport.nameText1(String(describing: workspace.path))) }
            try MinecraftDirectoryScan.checkIdentifier(name)
            names.insert(name.precomposedStringWithCanonicalMapping.lowercased())
        }
        return names
    }

    public static func pending(directoryID: UUID, paths: LauncherPaths) throws -> [RepositoryImportRecovery] {
        let state = try StateStore.load(paths)
        guard let directory = state.gameDirectories?.first(where: { $0.id == directoryID }), directory.isMinecraft else { return [] }
        try directory.validateAvailability()
        let root = try LauncherPaths.safePath(".ruri/imports", within: directory.url)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileTree.children(in: root).filter { UUID(uuidString: $0.lastPathComponent) != nil }.map { workspace in
            let journal = try RepositoryImportTransaction.read(workspace, directory: directory)
            return .init(id: journal.instance.id, name: journal.instance.name, workspace: workspace, canFinish: journal.phase == .published,
                         registered: state.instances.contains { $0.id == journal.instance.id }, copySource: journal.copySource)
        }
    }
    @discardableResult public static func recover(_ id: UUID, directoryID: UUID, finish: Bool, paths: LauncherPaths) throws -> URL? {
        let state = try StateStore.load(paths)
        guard let directory = state.gameDirectories?.first(where: { $0.id == directoryID }),
              let recovery = try pending(directoryID: directoryID, paths: paths).first(where: { $0.id == id }) else { throw RuriError.message(Messages.CoreRepositoryImport.recoveryText1) }
        return try RepositoryImportTransaction.recover(recovery, directory: directory, paths: paths, finish: finish)
    }
    static func requireNameAvailable(_ name: String, directory: GameDirectory, paths: LauncherPaths) throws {
        for pending in try pending(directoryID: directory.id, paths: paths) {
            let journal = try RepositoryImportTransaction.read(pending.workspace, directory: directory)
            guard journal.instance.repositoryVersionID?.localizedCaseInsensitiveCompare(name) != .orderedSame else {
                throw RuriError.message(Messages.CoreRepositoryImport.journalText1)
            }
        }
    }
    static func requireDirectoryAvailable(_ id: UUID, paths: LauncherPaths) throws {
        guard try pending(directoryID: id, paths: paths).isEmpty else { throw RuriError.message(Messages.CoreRepositoryImport.requireDirectoryAvailableText1) }
    }
    static func requireDirectoryAvailable(_ directory: GameDirectory) throws {
        guard directory.isMinecraft else { return }
        try directory.validateAvailability()
        let root = try LauncherPaths.safePath(".ruri/imports", within: directory.url)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        guard try !FileTree.children(in: root).contains(where: { UUID(uuidString: $0.lastPathComponent) != nil }) else {
            throw RuriError.message(Messages.CoreRepositoryImport.rootText1)
        }
    }
}
