import Foundation
import Darwin

public struct CustomRunDirectoryRelocationPreview: Identifiable, Sendable {
    public struct Instance: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let usesDirectory: Bool
    }
    public let id: UUID
    public let instanceID: UUID
    public let source: URL
    public let target: URL
    public let instances: [Instance]
    let original: CustomRunDirectory
    let replacement: CustomRunDirectory
    let identity: RunDirectoryCopyJournal.Identity
    let bindings: [CustomRunDirectoryBinding]
}

struct CustomRunDirectoryBinding: Equatable, Sendable {
    let instanceID: UUID
    let directoryID: UUID
    let mode: GameRunDirectory
    init(_ instance: GameInstance) {
        instanceID = instance.id; directoryID = instance.directoryID ?? GameDirectory.defaultID; mode = instance.runDirectory ?? .isolated
    }
}

/// Rebinds a moved game root without moving or merging any game files. Both
/// previews and commits hold the same locks as normal users of that root.
public actor CustomRunDirectoryRelocation {
    let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }

    public func preview(instanceID: UUID, target: URL) throws -> CustomRunDirectoryRelocationPreview {
        let state = try StateStore.load(paths)
        guard let original = state.instances.first(where: { $0.id == instanceID })?.customRunDirectory else { throw RuriError.message("此实例没有保存过自定义运行目录。") }
        let replacement = try original.relocated(to: target, paths: paths.configured(with: state))
        try validateOriginal(original, replacement: replacement)
        let affected = affectedInstances(state, original: original)
        let changed = replacing(original, with: replacement, in: state)
        let access = try CustomRunDirectoryRelocationAccess(paths: paths, state: state, changed: changed, affected: affected, replacement: replacement)
        defer { withExtendedLifetime(access) {} }
        return .init(id: UUID(), instanceID: instanceID, source: original.url, target: replacement.url,
                     instances: affected.map { .init(id: $0.id, name: $0.name, usesDirectory: $0.runDirectory == .custom) },
                     original: original, replacement: replacement, identity: try .read(replacement.url), bindings: affected.map(CustomRunDirectoryBinding.init))
    }

    public func apply(_ preview: CustomRunDirectoryRelocationPreview) throws -> PersistentState {
        let state = try StateStore.load(paths)
        try validate(preview, state: state)
        let affected = affectedInstances(state, original: preview.original)
        let changed = replacing(preview.original, with: preview.replacement, in: state)
        let access = try CustomRunDirectoryRelocationAccess(paths: paths, state: state, changed: changed, affected: affected, replacement: preview.replacement)
        defer { withExtendedLifetime(access) {} }
        try Task.checkCancellation()
        return try StateStore.update(paths) { latest in
            try validate(preview, state: latest)
            latest = replacing(preview.original, with: preview.replacement, in: latest)
        }
    }

    private func affectedInstances(_ state: PersistentState, original: CustomRunDirectory) -> [GameInstance] {
        state.instances.filter { $0.customRunDirectory?.isSameLocation(as: original) == true }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private func replacing(_ original: CustomRunDirectory, with replacement: CustomRunDirectory, in state: PersistentState) -> PersistentState {
        var result = state
        for index in result.instances.indices where result.instances[index].customRunDirectory?.isSameLocation(as: original) == true {
            result.instances[index].customRunDirectory?.url = replacement.url
            result.instances[index].customRunDirectory?.bookmark = replacement.bookmark
        }
        return result
    }
    private func validateOriginal(_ original: CustomRunDirectory, replacement: CustomRunDirectory) throws {
        if !original.isSameLocation(as: replacement), (try? original.validateAvailability()) != nil {
            throw RuriError.message("原目录仍可访问，所选位置可能是它的副本。若要改用另一份游戏数据，请使用“切换运行目录”，或先在 Finder 中完成原目录的移动。")
        }
    }
    private func validate(_ preview: CustomRunDirectoryRelocationPreview, state: PersistentState) throws {
        let affected = affectedInstances(state, original: preview.original)
        guard affected.contains(where: { $0.id == preview.instanceID }), affected.map(CustomRunDirectoryBinding.init) == preview.bindings else {
            throw RuriError.message("使用此目录的实例或其目录策略已经改变，请重新预览。")
        }
        try validateOriginal(preview.original, replacement: preview.replacement)
        try preview.replacement.validateAvailability()
        guard preview.identity.matches(preview.replacement.url) else { throw RuriError.message("所选文件夹在预览后被替换或移动，请重新选取原目录。") }
        try paths.configured(with: replacing(preview.original, with: preview.replacement, in: state)).validateDirectoryConfiguration()
    }
}

private final class CustomRunDirectoryRelocationAccess {
    private var instanceLeases: [GameRunLease] = []
    private var rootLease: SharedGameDirectoryLease?
    private var operations: [GameDataOperationLock] = []
    private var worlds: [Int32] = []
    init(paths: LauncherPaths, state: PersistentState, changed: PersistentState, affected: [GameInstance], replacement: CustomRunDirectory) throws {
        let current = paths.configured(with: state), relocated = paths.configured(with: changed)
        try relocated.validateDirectoryConfiguration()
        // Claim each active instance's metadata once, then the shared game root
        // once. Acquiring a full custom lease for every alias would self-block.
        for instance in affected where instance.runDirectory == .custom {
            var metadataOnly = instance; metadataOnly.runDirectory = .isolated
            instanceLeases.append(try GameRunLease.acquire(paths: current.including(metadataOnly), instanceID: instance.id))
        }
        guard var representative = affected.first else { throw RuriError.message("没有实例引用此目录。") }
        representative.runDirectory = .custom; representative.customRunDirectory = replacement
        let checked = relocated.including(representative)
        rootLease = try SharedGameDirectoryLease.acquire(paths: checked, instanceID: representative.id, ignoringSession: nil)
        for name in [".content-operation.lock", ".world-operation.lock", ".location-registration.lock"] {
            let lock = GameDataOperationLock(); try lock.acquire(directory: checked.gameDataState(representative.id), name: name); operations.append(lock)
        }
        for name in ["content-transaction", "world-restore"] where FileManager.default.fileExists(atPath: checked.gameDataState(representative.id).appendingPathComponent(name).path) {
            throw RuriError.message("此目录仍有未完成的内容或存档操作，请恢复原路径并处理后再重新定位。")
        }
        worlds = try InstanceTransfer.lockWorlds(replacement.url)
        try replacement.validateAvailability()
    }
    deinit { worlds.forEach { close($0) } }
}
