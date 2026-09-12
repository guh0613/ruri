import RuriLocalization
import Foundation
import Darwin

struct ModpackUpdateTarget: Codable, Hashable, Sendable {
    enum Scope: String, Codable, Sendable { case game, metadata, version, resources, content }
    let scope: Scope
    let path: String
    func url(instance: GameInstance, paths: LauncherPaths) throws -> URL {
        let root: URL
        switch scope {
        case .game: root = paths.game(instance.id)
        case .metadata: root = paths.instance(instance.id)
        case .version: root = paths.versionDirectory(instance.id)
        case .resources: root = try paths.resources(for: instance).root
        case .content: root = paths.gameDataState(instance.id)
        }
        return try LauncherPaths.safePath(path, within: root)
    }
}

struct ModpackUpdateJournal: Codable, Sendable {
    struct File: Codable, Sendable {
        let target: ModpackUpdateTarget
        let group: String
        let before: String?
        let after: String?
    }
    let id: UUID
    let original: GameInstance
    let updated: GameInstance
    let files: [File]
}

struct ModpackReplacement: Sendable {
    let target: ModpackUpdateTarget
    let group: String
    let source: URL?
}

public enum ModpackUpdateStore {
    static func pending(_ id: UUID, paths: LauncherPaths) -> URL { paths.instance(id).appendingPathComponent("modpack-update-transaction") }
    static func previous(_ id: UUID, paths: LauncherPaths) -> URL { paths.instance(id).appendingPathComponent("previous-modpack-update") }
    public static func hasPending(paths: LauncherPaths, instanceID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: pending(instanceID, paths: paths).appendingPathComponent("journal.json").path)
    }
    public static func hasBackup(paths: LauncherPaths, instanceID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: previous(instanceID, paths: paths).appendingPathComponent("journal.json").path)
    }
    static func requireAvailable(paths: LauncherPaths, instanceID: UUID) throws {
        guard !hasPending(paths: paths, instanceID: instanceID) else { throw RuriError.message(Messages.CoreModpackUpdateStore.updateRecoveryRequired) }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        for other in state.instances where other.id != instanceID && hasPending(paths: current, instanceID: other.id) {
            if MinecraftGameDataFiles.sameLocation(paths.game(instanceID), current.game(other.id)) {
                throw RuriError.message(Messages.CoreModpackUpdateStore.sharedDirectoryUpdatePending(other.name))
            }
        }
    }
    private static func read(_ root: URL) throws -> ModpackUpdateJournal {
        try JSONDecoder().decode(ModpackUpdateJournal.self, from: RunDirectoryCopyGuard.read(root.appendingPathComponent("journal.json"), limit: 64 * 1024 * 1024))
    }
    static func replace(_ target: URL, from source: URL?) throws {
        if let source {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = target.deletingLastPathComponent().appendingPathComponent(".ruri-update-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.copyItem(at: source, to: temporary)
            guard rename(temporary.path, target.path) == 0 else { throw RuriError.message(Messages.CoreModpackUpdateStore.updateFileSaveFailed(target.lastPathComponent)) }
        } else if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }
    static func applyFields(_ update: GameInstance, to latest: inout GameInstance) {
        latest.gameVersion = update.gameVersion; latest.loader = update.loader; latest.loaderVersion = update.loaderVersion
        latest.importedInstallation = update.importedInstallation; latest.repositoryComponents = update.repositoryComponents
        latest.packLibraries = update.packLibraries; latest.supportedJavaMajors = update.supportedJavaMajors
        latest.extraJVMArguments = update.extraJVMArguments; latest.extraGameArguments = update.extraGameArguments
        latest.launchOverrides = update.launchOverrides; latest.installed = true
        latest.lastModpackUpdateID = update.lastModpackUpdateID
    }
    static func mergedRecords(_ records: [ManagedContent], replacements: [ModpackReplacement], instance: GameInstance, paths: LauncherPaths) throws -> [ManagedContent] {
        func projected(_ path: String) throws -> URL? {
            if let item = replacements.first(where: { $0.target.scope == .game && $0.target.path == path }) { return item.source }
            return try LauncherPaths.safePath(path, within: paths.game(instance.id))
        }
        var seen = Set<String>(), result: [ManagedContent] = []
        for original in records where !seen.contains(original.id) {
            var record = original
            for _ in 0..<2 {
                if let file = try projected(record.relativePath), DownloadManager.valid(file, item: .init(url: nil, destination: file, sha1: record.sha1, sha512: record.sha512, md5: record.md5, size: record.size)) {
                    result.append(record); seen.insert(record.id); break
                }
                record.enabled.toggle()
            }
        }
        return result
    }
    static func commit(id: UUID, original: GameInstance, updated: GameInstance, replacements: [ModpackReplacement], paths: LauncherPaths) throws -> PersistentState {
        let directory = pending(original.id, paths: paths)
        guard !hasPending(paths: paths, instanceID: original.id) else { throw RuriError.message(Messages.CoreModpackUpdateStore.previousUpdateRecoveryRequired) }
        // Older launchers must stop reading this state before any pack file can
        // change, including when this is the first update after upgrading Ruri.
        if try StateStore.load(paths).schemaVersion < 16 { try StateStore.update(paths) { _ in } }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("files"), withIntermediateDirectories: true)
        var files: [ModpackUpdateJournal.File] = []
        let destinations = try replacements.map { try $0.target.url(instance: original, paths: paths).standardizedFileURL.resolvingSymlinksInPath().path.lowercased() }
        guard Set(destinations).count == replacements.count else { throw RuriError.message(Messages.CoreModpackUpdateStore.duplicateUpdateDestinations) }
        do {
            for (index, item) in replacements.enumerated() {
                try Task.checkCancellation()
                let target = try item.target.url(instance: original, paths: paths)
                let before = try ModpackUpdatePlanner.digest(target)
                if before != nil { try FileManager.default.copyItem(at: target, to: directory.appendingPathComponent("files/\(index)")) }
                let after = try item.source.flatMap(ModpackUpdatePlanner.digest)
                files.append(.init(target: item.target, group: item.group, before: before, after: after))
            }
            let journal = ModpackUpdateJournal(id: id, original: original, updated: updated, files: files)
            try JSONEncoder().encode(journal).write(to: directory.appendingPathComponent("journal.json"), options: .atomic)
            let saved = try StateStore.update(paths) { state in
                guard let index = state.instances.firstIndex(where: { $0.id == original.id }), state.instances[index] == original else {
                    throw RuriError.message(Messages.CoreModpackUpdateStore.instanceSettingsChangedBeforeCommit)
                }
                for item in replacements { try replace(item.target.url(instance: original, paths: paths), from: item.source) }
                applyFields(updated, to: &state.instances[index])
            }
            try finish(journal, directory: directory, paths: paths)
            return saved
        } catch {
            if hasPending(paths: paths, instanceID: original.id) {
                do { _ = try recoverFiles(original.id, paths: paths) }
                catch { throw RuriError.message(Messages.CoreModpackUpdateStore.updateFailedRecoveryRequired(error.localizedDescription)) }
            } else { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }
    private static func finish(_ journal: ModpackUpdateJournal, directory: URL, paths: LauncherPaths) throws {
        let destination = previous(journal.original.id, paths: paths)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: directory, to: destination)
    }
    private static func recoverFiles(_ id: UUID, paths: LauncherPaths) throws -> PersistentState {
        let directory = pending(id, paths: paths), journal = try read(directory)
        let state = try StateStore.load(paths)
        guard journal.original.id == id, let instance = state.instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CoreModpackUpdateStore.updateInstanceMissing) }
        if instance.lastModpackUpdateID == journal.id { try finish(journal, directory: directory, paths: paths); return state }
        for (index, file) in journal.files.enumerated() where file.before != nil {
            guard try ModpackUpdatePlanner.digest(directory.appendingPathComponent("files/\(index)")) == file.before else { throw RuriError.message(Messages.CoreModpackUpdateStore.incompleteRecoveryBackup) }
        }
        for (index, file) in journal.files.enumerated() {
            try replace(file.target.url(instance: journal.original, paths: paths), from: file.before == nil ? nil : directory.appendingPathComponent("files/\(index)"))
        }
        try FileManager.default.removeItem(at: directory)
        return state
    }
    public static func recover(instanceID: UUID, paths: LauncherPaths) throws -> PersistentState {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard hasPending(paths: current, instanceID: instanceID) else { return state }
        let lease = try InstanceLocationLease.acquireForMoveRecovery(paths: current, instanceID: instanceID)
        defer { withExtendedLifetime(lease) {} }
        return try recoverFiles(instanceID, paths: current)
    }
    static func rollback(instance: GameInstance, paths: LauncherPaths) throws -> (PersistentState, Int) {
        let directory = previous(instance.id, paths: paths), old = try read(directory)
        guard old.original.id == instance.id, instance.lastModpackUpdateID == old.id,
              old.updated.gameVersion == instance.gameVersion, old.updated.loader == instance.loader, old.updated.loaderVersion == instance.loaderVersion else {
            throw RuriError.message(Messages.CoreModpackUpdateStore.componentsChangedSinceUpdate)
        }
        var preserved = Set<String>()
        for file in old.files {
            if try ModpackUpdatePlanner.digest(file.target.url(instance: instance, paths: paths)) != file.after {
                guard file.target.scope == .game || file.target.scope == .content else { throw RuriError.message(Messages.CoreModpackUpdateStore.modifiedLaunchSettingsPreserved) }
                if file.target.scope == .game { preserved.insert(file.group) }
            }
        }
        var replacements: [ModpackReplacement] = []
        for (index, file) in old.files.enumerated() where !preserved.contains(file.group) {
            let source = file.before == nil ? nil : directory.appendingPathComponent("files/\(index)")
            if let source, try ModpackUpdatePlanner.digest(source) != file.before { throw RuriError.message(Messages.CoreModpackUpdateStore.backupCorrupted) }
            if file.target.scope == .content { continue }
            replacements.append(.init(target: file.target, group: file.group, source: source))
        }
        if let index = old.files.firstIndex(where: { $0.target.scope == .content }) {
            let file = old.files[index]
            let currentURL = try file.target.url(instance: instance, paths: paths)
            let currentRecords = FileManager.default.fileExists(atPath: currentURL.path) ? try JSONDecoder().decode([ManagedContent].self, from: RunDirectoryCopyGuard.read(currentURL, limit: 64 * 1024 * 1024)) : []
            let oldRecords = file.before == nil ? [] : try JSONDecoder().decode([ManagedContent].self, from: RunDirectoryCopyGuard.read(directory.appendingPathComponent("files/\(index)"), limit: 64 * 1024 * 1024))
            let merged = try mergedRecords(oldRecords + currentRecords, replacements: replacements, instance: instance, paths: paths)
            let source = directory.appendingPathComponent("rollback-content.json")
            try JSONEncoder().encode(merged).write(to: source, options: .atomic)
            replacements.append(.init(target: file.target, group: file.group, source: source))
        }
        var restored = instance
        applyFields(old.original, to: &restored)
        if instance.extraJVMArguments != old.updated.extraJVMArguments { restored.extraJVMArguments = instance.extraJVMArguments }
        if instance.extraGameArguments != old.updated.extraGameArguments { restored.extraGameArguments = instance.extraGameArguments }
        restored.launchOverrides = instance.launchOverrides
        if var overrides = restored.launchOverrides {
            if overrides.jvmArguments == old.updated.launchOverrides?.jvmArguments { overrides.jvmArguments = old.original.launchOverrides?.jvmArguments }
            if overrides.gameArguments == old.updated.launchOverrides?.gameArguments { overrides.gameArguments = old.original.launchOverrides?.gameArguments }
            restored.launchOverrides = overrides
        }
        let id = UUID(); restored.lastModpackUpdateID = id
        let state = try commit(id: id, original: instance, updated: restored, replacements: replacements, paths: paths)
        return (state, preserved.count)
    }
}
