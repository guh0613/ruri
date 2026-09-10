import Foundation
import Darwin

public struct GameRunDirectoryChangePreview: Identifiable, Sendable {
    public let id: UUID
    public let instanceID: UUID
    public let instanceName: String
    public let source: URL
    public let target: URL
    public let sourceMode: GameRunDirectory
    public let targetMode: GameRunDirectory
    public let targetCustomDirectory: CustomRunDirectory?
    public let createdAt: Date
    public var sourceFileCount: Int { sourceSnapshot.fileCount }
    public var sourceBytes: Int64 { sourceSnapshot.bytes }
    public var targetFileCount: Int { targetSnapshot.fileCount }
    public var targetBytes: Int64 { targetSnapshot.bytes }
    public var canCopyToTarget: Bool { targetSnapshot.isEmpty && copyIssue == nil }
    public let copyIssue: String?
    public let otherInstances: [String]
    let instance: GameInstance
    let sourceSnapshot: RunDirectorySnapshot
    let targetSnapshot: RunDirectorySnapshot
}

struct RunDirectorySnapshot: Equatable, Sendable {
    let game: [FileTree.Entry]
    let metadata: [FileTree.Entry]
    var fileCount: Int { (game + metadata).filter { !$0.directory }.count }
    var bytes: Int64 { (game + metadata).filter { !$0.directory }.reduce(0) { $0 + $1.size } }
    var isEmpty: Bool { fileCount == 0 }
    static func read(paths: LauncherPaths, instanceID: UUID) throws -> RunDirectorySnapshot {
        let fm = FileManager.default, gameRoot = paths.game(instanceID), metadataRoot = paths.gameDataState(instanceID)
        let reserved = Set(MinecraftGameDataFiles.reservedNames(paths: paths, instanceID: instanceID).map(MinecraftGameDataFiles.key))
        var game: [FileTree.Entry] = []
        if fm.fileExists(atPath: gameRoot.path) {
            let excluded = Set(try FileTree.children(in: gameRoot).filter { reserved.contains(MinecraftGameDataFiles.key($0.lastPathComponent)) }.map(\.lastPathComponent))
            game = try FileTree.entries(in: gameRoot, excluding: excluded)
        }
        var metadata: [FileTree.Entry] = []
        for name in ["content.json", "world-backups"] {
            let url = try LauncherPaths.safePath(name, within: metadataRoot)
            guard fm.fileExists(atPath: url.path) else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw RuriError.message("游戏内容记录或备份包含不支持的文件：\(name)") }
            metadata.append(.init(url: url, path: name, directory: values.isDirectory == true, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
            if values.isDirectory == true {
                metadata += try FileTree.entries(in: url).map { .init(url: $0.url, path: name + "/" + $0.path, directory: $0.directory, size: $0.size, modified: $0.modified) }
            }
        }
        return .init(game: game, metadata: metadata)
    }
}

/// Holds both game locations while inspecting or publishing a directory change.
/// File-operation locks additionally prevent another process from recovering a
/// transaction in either source or destination during the change.
final class RunDirectoryChangeAccess {
    let instance: GameInstance
    let sourcePaths: LauncherPaths
    let targetPaths: LauncherPaths
    let sourceLease: GameRunLease
    let targetLease: SharedGameDirectoryLease?
    var operations: [GameDataOperationLock] = []
    var worldLocks: [Int32] = []
    init(instance: GameInstance, paths: LauncherPaths, target: GameRunDirectory, customDirectory: CustomRunDirectory? = nil, directoryChangeID: UUID? = nil) throws {
        self.instance = instance; sourcePaths = paths
        var changed = instance; changed.runDirectory = target
        if target == .custom { changed.customRunDirectory = customDirectory ?? instance.customRunDirectory }
        targetPaths = paths.including(changed)
        try targetPaths.validateDirectoryConfiguration()
        sourceLease = try GameRunLease.acquire(paths: paths, instanceID: instance.id, directoryChangeID: directoryChangeID)
        targetLease = target != .isolated ? try SharedGameDirectoryLease.acquire(paths: targetPaths, instanceID: instance.id, ignoringSession: nil, directoryChangeID: directoryChangeID) : nil
        guard try !GameSessionStore.list(paths: paths, instanceID: instance.id).contains(where: { !$0.state.isFinished }) else {
            throw RuriError.message("此实例仍有尚未收尾的运行记录，请先在运行历史中确认或恢复，再切换目录。")
        }
    }
    func lockFiles() throws {
        for paths in [sourcePaths, targetPaths] {
            try paths.validateInstanceLocation(instance.id)
            for name in [".content-operation.lock", ".world-operation.lock"] {
                let lock = GameDataOperationLock()
                try lock.acquire(directory: paths.gameDataState(instance.id), name: name)
                operations.append(lock)
            }
            for name in ["content-transaction", "world-restore"] where FileManager.default.fileExists(atPath: paths.gameDataState(instance.id).appendingPathComponent(name).path) {
                throw RuriError.message("此目录还有未完成的内容或存档操作，请先恢复这些操作。")
            }
            worldLocks += try InstanceTransfer.lockWorlds(paths.game(instance.id))
        }
    }
    deinit { worldLocks.forEach { close($0) } }
}

public actor GameRunDirectoryChange {
    let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }

    public func preview(instanceID: UUID, target: GameRunDirectory, customDirectory: CustomRunDirectory? = nil) async throws -> GameRunDirectoryChangePreview {
        let state = try StateStore.load(paths)
        let current = paths.configured(with: state)
        let instance = try find(instanceID, in: state)
        let custom = target == .custom ? (customDirectory ?? instance.customRunDirectory) : nil
        try validateChange(instance, to: target, customDirectory: custom, paths: current)
        let access = try await acquire(instance: instance, paths: current, target: target, customDirectory: custom)
        defer { withExtendedLifetime(access) {} }
        let sourceSnapshot = try RunDirectorySnapshot.read(paths: current, instanceID: instanceID)
        let targetSnapshot = try RunDirectorySnapshot.read(paths: access.targetPaths, instanceID: instanceID)
        let copyIssue = MinecraftGameDataFiles.copyIssue(source: sourceSnapshot, sourcePaths: current, targetPaths: access.targetPaths, instanceID: instanceID)
        let others = state.instances.filter { other in
            other.id != instanceID && current.game(other.id).standardizedFileURL.resolvingSymlinksInPath() == access.targetPaths.game(instanceID).standardizedFileURL.resolvingSymlinksInPath()
        }.map(\.name)
        return GameRunDirectoryChangePreview(id: UUID(), instanceID: instanceID, instanceName: instance.name,
                                             source: current.game(instanceID), target: access.targetPaths.game(instanceID), sourceMode: instance.runDirectory ?? .isolated,
                                             targetMode: target, targetCustomDirectory: custom, createdAt: Date(), copyIssue: copyIssue, otherInstances: others, instance: instance,
                                             sourceSnapshot: sourceSnapshot, targetSnapshot: targetSnapshot)
    }

    /// Changes only the binding. Both game trees and their associated records
    /// remain where they are, so returning to a previous directory restores it.
    public func useExisting(_ preview: GameRunDirectoryChangePreview) async throws -> PersistentState {
        let state = try StateStore.load(paths)
        let current = paths.configured(with: state)
        let instance = try find(preview.instanceID, in: state)
        try validatePreviewBinding(preview, instance: instance, paths: current)
        let access = try await acquire(instance: instance, paths: current, target: preview.targetMode, customDirectory: preview.targetCustomDirectory)
        defer { withExtendedLifetime(access) {} }
        try validateSnapshots(preview, access: access)
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: access.targetPaths.game(instance.id), withIntermediateDirectories: true)
        return try commit(preview)
    }

    func find(_ id: UUID, in state: PersistentState) throws -> GameInstance {
        guard let instance = state.instances.first(where: { $0.id == id }) else { throw RuriError.message("这个实例已被移除，请刷新后重试。") }
        return instance
    }
    func validateChange(_ instance: GameInstance, to target: GameRunDirectory, customDirectory: CustomRunDirectory? = nil, paths: LauncherPaths) throws {
        try paths.validateBinding(instance)
        guard instance.name.count <= 1024 else { throw RuriError.message("实例名称过长，请先缩短名称再调整目录。") }
        if target == .custom {
            guard let customDirectory else { throw RuriError.message("请先选择自定义运行目录。") }
            try paths.checkCustomRunDirectory(customDirectory)
            try customDirectory.validateAvailability()
        }
        if (instance.runDirectory ?? .isolated) == target {
            guard target == .custom, let customDirectory, instance.customRunDirectory?.isSameLocation(as: customDirectory) == false else { throw RuriError.message("实例已经使用这个运行目录。") }
        }
        var changed = instance; changed.runDirectory = target
        if target == .custom { changed.customRunDirectory = customDirectory }
        guard !MinecraftGameDataFiles.sameLocation(paths.game(instance.id), paths.including(changed).game(instance.id)) else {
            throw RuriError.message("所选目录就是当前游戏目录，无需切换。")
        }
        if target != .isolated, try ModpackRegistry.load(paths: paths, instanceID: instance.id) != nil || FileManager.default.fileExists(atPath: paths.instance(instance.id).appendingPathComponent("source-mcbbs.packmeta").path) {
            throw RuriError.message("整合包保持独立运行目录，以保留包的配置与更新记录。")
        }
    }
    func validatePreviewBinding(_ preview: GameRunDirectoryChangePreview, instance: GameInstance, paths: LauncherPaths) throws {
        try validateChange(instance, to: preview.targetMode, customDirectory: preview.targetCustomDirectory, paths: paths)
        if preview.sourceMode == .custom {
            guard let current = instance.customRunDirectory, let original = preview.instance.customRunDirectory, current.isSameLocation(as: original) else { throw RuriError.message("自定义目录身份已经变化，请重新预览。") }
        }
        var target = instance; target.runDirectory = preview.targetMode
        if preview.targetMode == .custom { target.customRunDirectory = preview.targetCustomDirectory }
        guard instance.directoryID == preview.instance.directoryID, instance.runDirectory == preview.instance.runDirectory,
              instance.repositoryVersionID == preview.instance.repositoryVersionID,
              instance.gameVersion == preview.instance.gameVersion, instance.loader == preview.instance.loader, instance.loaderVersion == preview.instance.loaderVersion,
              paths.game(instance.id) == preview.source, paths.including(target).game(instance.id) == preview.target else { throw RuriError.message("实例或目录位置已经变化，请重新预览。") }
    }
    func acquire(instance: GameInstance, paths: LauncherPaths, target: GameRunDirectory, customDirectory: CustomRunDirectory? = nil) async throws -> RunDirectoryChangeAccess {
        let access = try RunDirectoryChangeAccess(instance: instance, paths: paths, target: target, customDirectory: customDirectory)
        for location in [access.sourcePaths, access.targetPaths] {
            try await ContentManager(paths: location, instanceID: instance.id).recover()
            try await WorldManager(paths: location, instanceID: instance.id).recover()
        }
        try access.lockFiles()
        return access
    }
    func validateSnapshots(_ preview: GameRunDirectoryChangePreview, access: RunDirectoryChangeAccess) throws {
        guard try RunDirectorySnapshot.read(paths: access.sourcePaths, instanceID: preview.instanceID) == preview.sourceSnapshot,
              try RunDirectorySnapshot.read(paths: access.targetPaths, instanceID: preview.instanceID) == preview.targetSnapshot else {
            throw RuriError.message("预览后游戏文件或备份发生了变化，请刷新预览后再切换。")
        }
    }
    func commit(_ preview: GameRunDirectoryChangePreview) throws -> PersistentState {
        try StateStore.update(paths) { state in
            let instance = try find(preview.instanceID, in: state)
            try validatePreviewBinding(preview, instance: instance, paths: paths.configured(with: state))
            guard let index = state.instances.firstIndex(where: { $0.id == instance.id }) else { throw RuriError.message("实例已被移除。") }
            state.instances[index].runDirectory = preview.targetMode
            if preview.targetMode == .custom { state.instances[index].customRunDirectory = preview.targetCustomDirectory }
            state.instances[index].lastRunDirectoryChangeID = nil
        }
    }
}
