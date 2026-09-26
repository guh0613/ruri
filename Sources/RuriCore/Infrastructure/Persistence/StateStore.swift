import RuriLocalization
import Foundation
import Darwin

public enum StateStore {
    public static let currentSchemaVersion = 24
    public static func load(_ paths: LauncherPaths) throws -> PersistentState {
        guard FileManager.default.fileExists(atPath: paths.state.path) else { return PersistentState() }
        let result = try JSONDecoder().decode(PersistentState.self, from: Data(contentsOf: paths.state))
        guard (1...currentSchemaVersion).contains(result.schemaVersion) else { throw RuriError.message(Messages.CoreStateStore.newerDataVersion) }
        try validate(result, paths: paths)
        return result
    }

    /// Compare-and-swap by default. A known baseline also permits disjoint
    /// edits from another client, without overwriting its accounts or instances.
    @discardableResult public static func save(_ state: PersistentState, to paths: LauncherPaths, basedOn baseline: PersistentState? = nil) throws -> PersistentState {
        let fd = try acquire(paths); defer { close(fd) }
        let current = try load(paths)
        let result: PersistentState
        if current.revision == state.revision { result = state }
        else {
            guard let baseline, baseline.revision == state.revision else { throw conflict(Messages.CoreStateStore.dataUpdatedElsewhere.localized) }
            result = try merge(base: baseline, local: state, remote: current)
        }
        return try write(result, paths: paths)
    }

    /// A small synchronous mutation of the latest state under one process lock.
    /// No downloads or external processes belong inside this closure.
    @discardableResult public static func update(_ paths: LauncherPaths, _ mutation: (inout PersistentState) throws -> Void) throws -> PersistentState {
        let fd = try acquire(paths); defer { close(fd) }
        var state = try load(paths)
        try mutation(&state)
        return try write(state, paths: paths)
    }
    /// CLI and shared services use this for idempotent, revision-checked edits.
    @discardableResult public static func updateIfChanged(_ paths: LauncherPaths, expectedRevision: UUID? = nil, _ mutation: (inout PersistentState) throws -> Void) throws -> PersistentState {
        let fd = try acquire(paths); defer { close(fd) }
        let original = try load(paths)
        if let expectedRevision, original.revision != expectedRevision {
            throw OperationFailure("STATE_CONFLICT", Messages.CLIInterface.te8a7227e2180.localized, retryable: true)
        }
        var state = original
        try mutation(&state)
        guard state != original else { return original }
        return try write(state, paths: paths)
    }
    private static func validate(_ state: PersistentState, paths: LauncherPaths) throws {
        try JavaRuntimeStore.validate(state.settings.javaLocations ?? [])
        guard state.instances.allSatisfy({ $0.frozenMemory == nil }) else { throw RuriError.message(Messages.CoreStateStore.snapshotCannotOverwriteSettings) }
        guard Set(state.instances.map(\.id)).count == state.instances.count, Set(state.accounts.map(\.id)).count == state.accounts.count else { throw RuriError.message(Messages.CoreStateStore.duplicateInstancesOrAccounts) }
        for instance in state.instances {
            try instance.importedInstallation?.validate()
            if let icon = instance.iconPNG { try InstanceIconImage.validate(icon) }
        }
        try paths.configured(with: state).validateDirectoryConfiguration()
        let detached = state.detachedMinecraftFolders ?? []
        let directories = (state.gameDirectories ?? []).map(\.id) + detached.map(\.id)
        let instances = state.instances.map(\.id) + detached.flatMap { $0.instances.map(\.id) }
        guard Set(directories).count == directories.count, Set(instances).count == instances.count else {
            throw RuriError.message(Messages.CoreStateStore.duplicateDirectoryIdentities)
        }
        for folder in detached { try folder.validate(paths: paths) }
    }
    private static func write(_ input: PersistentState, paths: LauncherPaths) throws -> PersistentState {
        var state = input; state.schemaVersion = currentSchemaVersion; state.revision = UUID()
        try validate(state, paths: paths)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: paths.state, options: [.atomic])
        return state
    }
    private static func acquire(_ paths: LauncherPaths) throws -> Int32 {
        try paths.prepare()
        let file = try LauncherPaths.safePath(".ruri-state.lock", within: paths.root)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreStateStore.settingsLockFailed) }
        var info = stat(), lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(fd); throw RuriError.message(Messages.CoreStateStore.settingsLockFailed)
        }
        guard fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            close(fd); throw OperationFailure("RESOURCE_BUSY", Messages.CoreStateStore.saveInProgress.localized, retryable: true)
        }
        return fd
    }
    private static func conflict(_ field: String) -> OperationFailure {
        let parts = field.split(separator: ".").map(String.init)
        let labels = ["instances": Messages.CoreStateStore.sameInstance.localized, "accounts": Messages.CoreStateStore.sameAccount.localized, "gameDirectories": Messages.CoreStateStore.sameInstanceDirectory.localized, "detachedMinecraftFolders": Messages.CoreStateStore.retainedFolderRecord.localized, "settings": Messages.CoreStateStore.launcherSettings.localized,
                      "name": Messages.CoreStateStore.name.localized, "favorite": Messages.CoreStateStore.favoriteStatus.localized, "memoryMB": Messages.CoreStateStore.memory.localized, "javaPath": Messages.CoreStateStore.javaSelection.localized,
                      "width": Messages.CoreStateStore.windowWidth.localized, "height": Messages.CoreStateStore.windowHeight.localized, "appearance": Messages.CoreStateStore.appearance.localized, "downloadSource": Messages.CoreStateStore.downloadSource.localized,
                      "extraJVMArguments": Messages.CoreStateStore.jvmArguments.localized, "extraGameArguments": Messages.CoreStateStore.gameArguments.localized, "directoryID": Messages.CoreStateStore.owningFolder.localized,
                      "memory": Messages.CoreStateStore.memoryPolicy.localized, "defaultMemorySettings": Messages.CoreStateStore.defaultMemoryPolicy.localized]
        let description: String
        if let first = parts.first, let subject = labels[first] {
            if parts.count > 1, let field = parts.last.flatMap({ labels[$0] }) {
                description = Messages.CoreStateStore.fieldConflict(subject, field).localized
            } else if parts.count > 1 {
                description = Messages.CoreStateStore.subjectChangeConflict(subject).localized
            } else {
                description = Messages.CoreStateStore.subjectConflict(subject).localized
            }
        } else if ["selectedInstanceID", "selectedDirectoryID", "activeAccountID"].contains(field) { description = Messages.CoreStateStore.selectionChangedElsewhere.localized }
        else { description = field }
        return .init("STATE_CONFLICT", Messages.CoreStateStore.saveConflictPreservingOriginal(String(describing: description)).localized, retryable: true)
    }

    private static func merge(base: PersistentState, local: PersistentState, remote: PersistentState) throws -> PersistentState {
        func object(_ state: PersistentState) throws -> [String: Any] {
            guard var result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any] else { throw conflict(Messages.CoreStateStore.invalidDataFormat.localized) }
            result.removeValue(forKey: "revision"); result.removeValue(forKey: "schemaVersion")
            return result
        }
        var merged = try mergeObject(base: object(base), local: object(local), remote: object(remote), path: "")
        merged["schemaVersion"] = 2
        return try JSONDecoder().decode(PersistentState.self, from: JSONSerialization.data(withJSONObject: merged))
    }
    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        guard let a = a as? NSObject, let b = b as? NSObject else { return false }
        return a.isEqual(b)
    }
    private static func mergeObject(base: [String: Any], local: [String: Any], remote: [String: Any], path: String) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for key in Set(base.keys).union(local.keys).union(remote.keys) {
            let b = base[key], l = local[key], r = remote[key]
            let field = path.isEmpty ? key : path + "." + key
            if equal(l, b) { result[key] = r }
            else if equal(r, b) || equal(l, r) { result[key] = l }
            // Mode and limits form one policy. Combining two valid edits can
            // otherwise produce an initial heap larger than its new maximum,
            // or silently turn a manual edit into automatic allocation.
            else if field == "settings.defaultMemorySettings" || field.hasSuffix(".launchOverrides.memory") || field.hasSuffix(".customRunDirectory") || field.hasSuffix(".importedInstallation") { throw conflict(field) }
            else if let b = b as? [String: Any], let l = l as? [String: Any], let r = r as? [String: Any] {
                result[key] = try mergeObject(base: b, local: l, remote: r, path: field)
            } else if path.isEmpty && ["instances", "accounts", "gameDirectories"].contains(key) {
                result[key] = try mergeItems(base: b as? [[String: Any]] ?? [], local: l as? [[String: Any]] ?? [], remote: r as? [[String: Any]] ?? [], path: field)
            } else { throw conflict(field) }
        }
        return result
    }
    private static func mergeItems(base: [[String: Any]], local: [[String: Any]], remote: [[String: Any]], path: String) throws -> [[String: Any]] {
        func index(_ items: [[String: Any]]) throws -> [String: Any] {
            var result: [String: Any] = [:]
            for item in items {
                guard let id = item["id"] as? String, result[id] == nil else { throw conflict(path) }
                result[id] = item
            }
            return result
        }
        let result = try mergeObject(base: index(base), local: index(local), remote: index(remote), path: path)
        var seen = Set<String>()
        return (remote + local).compactMap { item in
            guard let id = item["id"] as? String, seen.insert(id).inserted else { return nil }
            return result[id] as? [String: Any]
        }
    }
}
