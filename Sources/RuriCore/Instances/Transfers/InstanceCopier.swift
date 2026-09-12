import RuriLocalization
import Foundation
import Darwin

public struct InstanceCopyOptions: Equatable, Sendable {
    public var includeWorlds: Bool
    public var includeBackups: Bool
    public init(includeWorlds: Bool = true, includeBackups: Bool = false) { self.includeWorlds = includeWorlds; self.includeBackups = includeBackups }
}
public struct InstanceCopyPreview: Identifiable, Sendable {
    public let id: UUID
    public let source: GameInstance
    public let copy: GameInstance
    public let sourceGame: URL
    public let destination: URL
    public let options: InstanceCopyOptions
    public var fileCount: Int { entries.filter { !$0.directory }.count + (installation?.fileCount ?? 0) }
    public var bytes: Int64 { entries.filter { !$0.directory }.reduce(0) { $0 + $1.size } + (installation?.bytes ?? 0) }
    let targetCollection: GameDirectory?
    let entries: [FileTree.Entry]
    let manifest: FileTreeManifest
    var installation: MinecraftInstallationCopy? = nil
}
public struct InstanceCopyRecovery: Sendable {
    public let owner: InstanceCopyOwner
    public let destination: URL
    public let workspace: URL
    public let committed: Bool
}

public actor InstanceCopier {
    let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public func preview(instanceID: UUID, name: String, directoryID: UUID, options: InstanceCopyOptions = .init()) async throws -> InstanceCopyPreview {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        let original = try instance(instanceID, in: state)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 256, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuriError.message(Messages.CoreInstanceCopier.copyNameInvalid) }
        var copy = original; copy.id = UUID(); copy.name = name; copy.createdAt = Date(); copy.lastPlayed = nil; copy.playTime = 0; copy.favorite = false
        copy.directoryID = directoryID; copy.runDirectory = .isolated; copy.customRunDirectory = nil; copy.lastRunDirectoryChangeID = nil; copy.lastInstanceMoveID = nil; copy.frozenMemory = nil
        let id = UUID(); copy.lastInstanceCopyID = id
        var collection = current.directories.first(where: { $0.id == directoryID }); collection?.bookmark = nil
        guard directoryID == GameDirectory.defaultID || collection != nil else { throw RuriError.message(Messages.CoreInstanceCopier.targetInstanceFolderMissing) }
        if current.isMinecraftDirectory(directoryID) {
            return try await repositoryPreview(original: original, copy: copy, id: id, collection: collection!, paths: current, options: options)
        }
        guard original.repositoryVersionID == nil else { throw RuriError.message(Messages.CoreInstanceCopier.minecraftFolderRequired) }
        let journal = InstanceCopyJournal(id: id, original: original, copy: copy, targetCollection: collection, createdAt: Date(), phase: .copying)
        try journal.validate()
        try journal.validateTarget(paths: current)
        let access = try await acquire(original, paths: current); defer { withExtendedLifetime(access) {} }
        let snapshot = try entries(original, paths: current, options: options)
        let manifest = try FileTreeManifest.capture(snapshot, requiringDirectories: ["minecraft"], rootAttributes: FileExtendedAttributes.capture(current.instance(original.id)))
        guard try entries(original, paths: current, options: options) == snapshot else { throw RuriError.message(Messages.CoreInstanceCopier.sourceChangedDuringPreview) }
        return .init(id: id, source: original, copy: copy, sourceGame: current.game(original.id), destination: try journal.destination(paths: current), options: options, targetCollection: collection, entries: snapshot, manifest: manifest)
    }

    public func copy(_ preview: InstanceCopyPreview, progress: @Sendable (RunDirectoryCopyProgress) -> Void = { _ in }) async throws -> RunDirectoryCopyResult {
        if preview.installation != nil { return try await copyToRepository(preview, progress: progress) }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        try validate(preview, state: state)
        let source = try instance(preview.source.id, in: state)
        let access = try await acquire(source, paths: current); defer { withExtendedLifetime(access) {} }
        progress(.init(phase: .verifying, completed: 0, total: 0, bytesCopied: 0, totalBytes: preview.bytes))
        try validateFiles(preview, paths: current)
        var journal = InstanceCopyJournal(id: preview.id, original: preview.source, copy: preview.copy, targetCollection: preview.targetCollection, createdAt: Date(), phase: .copying)
        try journal.validateTarget(paths: current)
        let root = try InstanceCopyJournal.root(paths: current, sourceID: source.id)
        let preparing = root.deletingLastPathComponent().appendingPathComponent(".preparing-\(journal.id.uuidString)")
        let workspace = try journal.workspace(paths: current), incoming = try journal.incoming(paths: current), destination = try journal.destination(paths: current)
        var activated = false
        var committed: PersistentState?
        let targetLocation = journal
        do {
            // Upgrade before activating a reservation that old clients cannot read.
            try StateStore.update(paths) { try validate(preview, state: $0) }
            try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: preparing, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try journal.save(paths: current, at: preparing)
            try RunDirectoryFileCopy.moveWithoutReplacing(preparing, to: root); activated = true
            try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard mkdir(workspace.path, S_IRWXU) == 0 else { throw RuriError.message(Messages.CoreInstanceCopier.copyWorkspaceConflict) }
            var bytes: Int64 = 0, completed = 0
            var lastProgress = Date.distantPast
            func validateLocations() throws { try current.validateInstanceLocation(source.id); try targetLocation.validateTarget(paths: current) }
            progress(.init(phase: .copying, completed: 0, total: preview.fileCount, bytesCopied: 0, totalBytes: preview.bytes))
            try RunDirectoryFileCopy.entries(preview.entries, to: incoming, validate: validateLocations) { amount, finished in
                bytes += amount; if finished { completed += 1 }
                if completed == preview.fileCount || Date().timeIntervalSince(lastProgress) >= 0.1 {
                    lastProgress = Date(); progress(.init(phase: .copying, completed: completed, total: preview.fileCount, bytesCopied: bytes, totalBytes: preview.bytes))
                }
            }
            try FileManager.default.createDirectory(at: incoming.appendingPathComponent("minecraft"), withIntermediateDirectories: true)
            try FileExtendedAttributes.copy(from: current.instance(source.id), to: incoming)
            progress(.init(phase: .verifying, completed: 0, total: 0, bytesCopied: 0, totalBytes: preview.bytes))
            try preview.manifest.requireMatch(in: incoming, ignoringTransientFiles: true)
            try rebindModpack(incoming, copy: journal.copy)
            try Task.checkCancellation()
            try validateFiles(preview, paths: current)
            let publishedManifest = try FileTreeManifest.capture(in: incoming, ignoringTransientFiles: true)
            journal.verificationDigest = try publishedManifest.save(to: root.appendingPathComponent("verification.json"))
            try InstanceCopyGuard.mark(journal, at: incoming)
            journal.stagedIdentity = try .read(incoming); journal.phase = .publishing; try journal.save(paths: current)
            let publicationBytes = try FileTree.entries(in: incoming, excluding: [InstanceCopyGuard.markerName]).filter { !$0.directory }.reduce(Int64(0)) { $0 + $1.size }
            progress(.init(phase: .publishing, completed: 0, total: 1, bytesCopied: 0, totalBytes: publicationBytes))
            var publishedBytes: Int64 = 0
            try RunDirectoryFileCopy.publish(incoming, to: destination, directory: true, excluding: [InstanceCopyGuard.markerName]) { identity in
                journal.publishedIdentity = identity; try journal.save(paths: current)
                try InstanceCopyGuard.mark(journal, at: destination)
            } validate: { try validateLocations() } progress: { amount in
                publishedBytes += amount
                progress(.init(phase: .publishing, completed: 0, total: 1, bytesCopied: publishedBytes, totalBytes: publicationBytes))
            }
            guard (journal.publishedIdentity ?? journal.stagedIdentity)?.matches(destination) == true else { throw RuriError.message(Messages.CoreInstanceCopier.publishedCopyChanged) }
            progress(.init(phase: .publishing, completed: 1, total: 1, bytesCopied: publicationBytes, totalBytes: publicationBytes))
            try Task.checkCancellation()
            progress(.init(phase: .verifying, completed: 0, total: 0, bytesCopied: 0, totalBytes: publicationBytes))
            try validateFiles(preview, paths: current)
            try verifyPublication(publishedManifest, at: destination)
            committed = try StateStore.update(paths) { latest in
                try validate(preview, state: latest)
                try journal.validateTarget(paths: paths.configured(with: latest))
                latest.instances.append(journal.copy); latest.selectedInstanceID = journal.copy.id; latest.selectedDirectoryID = journal.copy.directoryID
            }
            progress(.init(phase: .committed, completed: 1, total: 1, bytesCopied: preview.bytes, totalBytes: preview.bytes))
            journal.phase = .committed; try journal.save(paths: current)
            let remainder = try cleanup(journal, paths: current)
            return .init(state: committed!, preservedCopy: remainder, warning: remainder.map { _ in Messages.CoreInstanceCopier.copyCompletedWithTemporaryFiles.localized })
        } catch {
            if !activated { try? FileManager.default.removeItem(at: preparing); throw error }
            if committed == nil {
                do { let latest = try StateStore.load(paths); if latest.instances.first(where: { $0.id == journal.copy.id })?.lastInstanceCopyID == journal.id { committed = latest } }
                catch { throw RunDirectoryCopyFailure(message: Messages.CoreInstanceCopier.copyCommitUncertain(error.localizedDescription).localized, preservedCopy: nil, cancelled: Task.isCancelled) }
            }
            if let committed { return .init(state: committed, preservedCopy: nil, warning: Messages.CoreInstanceCopier.copyCommittedCleanupPending(error.localizedDescription).localized) }
            let reason = Task.isCancelled || error is CancellationError ? Messages.CoreInstanceCopier.copyCancelled.localized : Messages.CoreInstanceCopier.copyFailed(error.localizedDescription).localized
            do {
                let result = try abandon(journal, paths: current)
                throw RunDirectoryCopyFailure(message: reason + (result.warning.map { "\n" + $0 } ?? ""), preservedCopy: result.workspace, cancelled: Task.isCancelled || error is CancellationError)
            } catch let failure as RunDirectoryCopyFailure { throw failure }
            catch { throw RunDirectoryCopyFailure(message: Messages.CoreInstanceCopier.recoveryFailure(reason, error.localizedDescription).localized, preservedCopy: nil, cancelled: Task.isCancelled) }
        }
    }

    public func pending(instanceID: UUID) throws -> InstanceCopyRecovery? {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard let owner = try InstanceCopyGuard.owner(paths: current, instanceID: instanceID) else {
            guard let pending = try repositoryPending(instanceID: instanceID, state: state), let owner = pending.recovery.copySource else { return nil }
            return .init(owner: owner, destination: pending.directory.url.appendingPathComponent("versions/" + owner.copyName),
                         workspace: pending.recovery.workspace, committed: pending.recovery.registered)
        }
        let journal = try InstanceCopyJournal.load(paths: current, sourceID: owner.sourceID)
        let workspace = try journal.workspace(paths: current)
        return .init(owner: journal.owner, destination: try journal.destination(paths: current),
                     workspace: FileManager.default.fileExists(atPath: workspace.path) ? workspace : try InstanceCopyJournal.root(paths: current, sourceID: owner.sourceID),
                     committed: state.instances.first(where: { $0.id == journal.copy.id })?.lastInstanceCopyID == journal.id)
    }
    public func recover(sourceID: UUID, transactionID: UUID) throws -> RunDirectoryCopyResult {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        if let pending = try repositoryPending(instanceID: sourceID, state: state), pending.recovery.copySource?.transactionID == transactionID {
            let kept = try RepositoryImportStore.recover(pending.recovery.id, directoryID: pending.directory.id,
                                                        finish: pending.recovery.registered, paths: paths)
            return .init(state: try StateStore.load(paths), preservedCopy: kept, warning: kept.map { _ in Messages.CoreInstanceCopier.workFilesKept.localized })
        }
        let journal = try InstanceCopyJournal.load(paths: current, sourceID: sourceID)
        guard journal.id == transactionID else { throw RuriError.message(Messages.CoreInstanceCopier.pendingCopyChanged) }
        var source = try instance(sourceID, in: state); source.runDirectory = .isolated
        let lease = try GameRunLease.acquire(paths: current.including(source), instanceID: sourceID, directoryChangeID: journal.id)
        defer { withExtendedLifetime(lease) {} }
        let latest = try InstanceCopyJournal.load(paths: current, sourceID: sourceID)
        guard latest.id == journal.id else { throw RuriError.message(Messages.CoreInstanceCopier.copyRecordChanged) }
        let saved = try StateStore.load(paths), configured = paths.configured(with: saved)
        try latest.validateTarget(paths: configured)
        if let copy = saved.instances.first(where: { $0.id == latest.copy.id }) {
            guard copy.lastInstanceCopyID == latest.id, copy.directoryID == latest.copy.directoryID, copy.runDirectory == .isolated else { throw RuriError.message(Messages.CoreInstanceCopier.copyRegistrationMismatch) }
            let remainder = try cleanup(latest, paths: configured)
            return .init(state: saved, preservedCopy: remainder, warning: remainder.map { _ in Messages.CoreInstanceCopier.copyCleanupIncomplete.localized })
        }
        let result = try abandon(latest, paths: configured)
        return .init(state: saved, preservedCopy: result.workspace, warning: result.warning)
    }

    private func instance(_ id: UUID, in state: PersistentState) throws -> GameInstance {
        guard let value = state.instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CoreInstanceCopier.sourceRemoved) }; return value
    }
    private func validate(_ preview: InstanceCopyPreview, state: PersistentState) throws {
        let original = try instance(preview.source.id, in: state)
        guard !state.instances.contains(where: { $0.id == preview.copy.id }), original == preview.source else { throw RuriError.message(Messages.CoreInstanceCopier.sourceSettingsChanged) }
        let journal = InstanceCopyJournal(id: preview.id, original: original, copy: preview.copy, targetCollection: preview.targetCollection, createdAt: Date(), phase: .copying)
        try journal.validateTarget(paths: paths.configured(with: state))
    }
    private func validateFiles(_ preview: InstanceCopyPreview, paths: LauncherPaths) throws {
        let snapshot = try entries(preview.source, paths: paths, options: preview.options)
        guard snapshot == preview.entries,
              try FileTreeManifest.capture(snapshot, requiringDirectories: ["minecraft"], rootAttributes: FileExtendedAttributes.capture(paths.instance(preview.source.id))) == preview.manifest,
              try entries(preview.source, paths: paths, options: preview.options) == snapshot else { throw RuriError.message(Messages.CoreInstanceCopier.sourceFilesChanged) }
    }
    func acquire(_ instance: GameInstance, paths: LauncherPaths) async throws -> InstanceCopyAccess {
        let access = try InstanceCopyAccess(instance: instance, paths: paths)
        try await ContentManager(paths: paths, instanceID: instance.id).recover()
        try await WorldManager(paths: paths, instanceID: instance.id).recover()
        try access.lockFiles(); return access
    }
    private func entries(_ source: GameInstance, paths: LauncherPaths, options: InstanceCopyOptions) throws -> [FileTree.Entry] {
        let pack = try ModpackRegistry.load(paths: paths, instanceID: source.id)
        var excluded = try InstanceTransfer.exclusions(paths.game(source.id), includeWorlds: options.includeWorlds)
        let declared = Set((pack?.files ?? []).compactMap { $0.path.split(separator: "/").first.map(String.init) }).subtracting(options.includeWorlds ? [".ruri"] : [".ruri", "saves"])
        excluded.subtract(declared)
        var result: [FileTree.Entry] = []
        if FileManager.default.fileExists(atPath: paths.game(source.id).path) {
            let game = paths.game(source.id)
            let attributes = try game.resourceValues(forKeys: [.contentModificationDateKey])
            result.append(.init(url: game, path: "minecraft", directory: true, size: 0, modified: attributes.contentModificationDate ?? .distantPast))
            result += try FileTree.entries(in: paths.game(source.id), excluding: excluded).map { .init(url: $0.url, path: "minecraft/" + $0.path, directory: $0.directory, size: $0.size, modified: $0.modified) }
        }
        for name in ["version.json", "natives", "source-mcbbs.packmeta", "modpack-state.json", "content.json"] + (source.importedInstallation != nil ? ["installation"] : []) + (options.includeBackups ? ["world-backups"] : []) {
            let root = ["content.json", "world-backups"].contains(name) ? paths.gameDataState(source.id) : paths.instance(source.id)
            let file = try LauncherPaths.safePath(name, within: root)
            guard FileManager.default.fileExists(atPath: file.path) else {
                if name == "version.json" && source.installed { throw RuriError.message(Messages.CoreInstanceCopier.installedManifestMissing) }
                if name == "installation" && source.installed { throw RuriError.message(Messages.CoreInstanceCopier.installationFolderMissing) }
                continue
            }
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else { throw RuriError.message(Messages.CoreInstanceCopier.unsupportedMetadataFiles(name)) }
            if name == "installation" && values.isDirectory != true { throw RuriError.message(Messages.CoreInstanceCopier.installationPathInvalid) }
            if name == "version.json" && source.installed {
                guard values.isRegularFile == true, (values.fileSize ?? .max) <= 8_388_608 else { throw RuriError.message(Messages.CoreInstanceCopier.invalidInstanceManifest) }
                let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: file))
                guard manifest.mainClass != nil, manifest.inheritsFrom == nil else { throw RuriError.message(Messages.CoreInstanceCopier.launchManifestNotReady) }
            }
            result.append(.init(url: file, path: name, directory: values.isDirectory == true, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
            if values.isDirectory == true { result += try FileTree.entries(in: file).map { .init(url: $0.url, path: name + "/" + $0.path, directory: $0.directory, size: $0.size, modified: $0.modified) } }
        }
        guard result.count <= 150_000, result.filter({ !$0.directory }).reduce(Int64(0), { $0 + $1.size }) <= 128 * 1024 * 1024 * 1024 else { throw RuriError.message(Messages.CoreInstanceCopier.copyLimitExceeded) }
        return result
    }
    private func rebindModpack(_ root: URL, copy: GameInstance) throws {
        let file = root.appendingPathComponent("modpack-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var record = try ModpackRegistry.read(file, game: root.appendingPathComponent("minecraft"))
        record.settings.id = copy.id; record.settings.directoryID = copy.directoryID; record.settings.runDirectory = .isolated
        record.settings.customRunDirectory = nil; record.settings.lastRunDirectoryChangeID = nil; record.settings.lastInstanceCopyID = nil; record.settings.lastInstanceMoveID = nil; record.settings.frozenMemory = nil
        try FileExtendedAttributes.rewrite(JSONEncoder().encode(record), at: file)
    }
    private func retire(_ journal: InstanceCopyJournal, paths: LauncherPaths) throws -> URL {
        let destination = try LauncherPaths.safePath("instance-copy-recovery/\(journal.original.id.uuidString)-\(journal.id.uuidString)-\(UUID().uuidString)", within: paths.root)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunDirectoryFileCopy.moveWithoutReplacing(InstanceCopyJournal.root(paths: paths, sourceID: journal.original.id), to: destination)
        return destination
    }
    private func cleanup(_ journal: InstanceCopyJournal, paths: LauncherPaths) throws -> URL? {
        try journal.validateTarget(paths: paths)
        let destination = try journal.destination(paths: paths)
        guard (journal.publishedIdentity ?? journal.stagedIdentity)?.matches(destination) == true else {
            throw RuriError.message(Messages.CoreInstanceCopier.destinationFolderUnavailable)
        }
        if let digest = journal.verificationDigest {
            let record = try InstanceCopyJournal.root(paths: paths, sourceID: journal.original.id).appendingPathComponent("verification.json")
            try verifyPublication(FileTreeManifest.load(from: record, expectedDigest: digest), at: destination)
        }
        try InstanceCopyGuard.clear(journal, at: destination)
        let record = try retire(journal, paths: paths), workspace = try journal.workspace(paths: paths)
        do {
            if FileManager.default.fileExists(atPath: workspace.path) {
                do { try FileManager.default.removeItem(at: workspace) } catch { return workspace }
            }
            try FileManager.default.removeItem(at: record); return nil
        } catch { return record }
    }
    private func verifyPublication(_ manifest: FileTreeManifest, at directory: URL) throws {
        // Older clients create these before checking a pending reservation.
        // Only tolerate regular, empty locks; never ignore data at these names.
        let locks: Set<String> = [".ruri-game.lock", ".content-operation.lock", ".world-operation.lock"]
        for name in locks {
            var info = stat()
            if lstat(directory.appendingPathComponent(name).path, &info) == 0 {
                guard info.st_mode & S_IFMT == S_IFREG, info.st_size == 0 else { throw RuriError.message(Messages.CoreInstanceCopier.unexpectedOperationLock) }
            } else if errno != ENOENT { throw RuriError.message(Messages.CoreInstanceCopier.lockUnavailable) }
        }
        try manifest.requireMatch(in: directory, excluding: locks.union([InstanceCopyGuard.markerName]), ignoringTransientFiles: true)
    }
    private func abandon(_ input: InstanceCopyJournal, paths: LauncherPaths) throws -> (workspace: URL, warning: String?) {
        try input.validateTarget(paths: paths)
        var journal = input; journal.phase = .recovering; try journal.save(paths: paths)
        let destination = try journal.destination(paths: paths), workspace = try journal.workspace(paths: paths)
        var warning: String?
        if (journal.publishedIdentity ?? journal.stagedIdentity)?.matches(destination) == true {
            try RunDirectoryFileCopy.returnToWorkspace(destination, workspace: workspace)
        } else {
            var info = stat()
            if lstat(destination.path, &info) == 0 { warning = Messages.CoreInstanceCopier.unknownTargetFolder(destination.path).localized }
            else if errno != ENOENT { throw RuriError.message(Messages.CoreInstanceCopier.targetStateUnconfirmed) }
        }
        let record = try retire(journal, paths: paths)
        return (FileManager.default.fileExists(atPath: workspace.path) ? workspace : record, warning)
    }
}

final class InstanceCopyAccess {
    let instance: GameInstance
    let paths: LauncherPaths
    let lease: GameRunLease
    var locks: [GameDataOperationLock] = []
    var worlds: [Int32] = []
    init(instance: GameInstance, paths: LauncherPaths) throws { self.instance = instance; self.paths = paths; lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id) }
    func lockFiles() throws {
        for name in [".content-operation.lock", ".world-operation.lock"] {
            let lock = GameDataOperationLock(); try lock.acquire(directory: paths.gameDataState(instance.id), name: name); locks.append(lock)
        }
        for name in ["content-transaction", "world-restore"] where FileManager.default.fileExists(atPath: paths.gameDataState(instance.id).appendingPathComponent(name).path) { throw RuriError.message(Messages.CoreInstanceCopier.pendingFileOperation) }
        worlds = try InstanceTransfer.lockWorlds(paths.game(instance.id))
    }
    deinit { worlds.forEach { close($0) } }
}
