import Foundation
import Darwin

/// Moving retires the original history, so every session must be readable and
/// finished. The history UI's best-effort list intentionally has weaker rules.
final class InstanceMoveAccess {
    let lease: GameRunLease
    private var operations: [GameDataOperationLock] = []
    private var worlds: [Int32] = []
    private init(lease: GameRunLease) { self.lease = lease }

    static func acquire(instance: GameInstance, paths: LauncherPaths) async throws -> InstanceMoveAccess {
        let result = InstanceMoveAccess(lease: try GameRunLease.acquire(paths: paths, instanceID: instance.id))
        try requireFinishedSessions(paths: paths, instanceID: instance.id)
        try await ContentManager(paths: paths, instanceID: instance.id).recover()
        try await WorldManager(paths: paths, instanceID: instance.id).recover()
        for name in [".content-operation.lock", ".world-operation.lock"] {
            let lock = GameDataOperationLock()
            try lock.acquire(directory: paths.gameDataState(instance.id), name: name); result.operations.append(lock)
        }
        for name in ["content-transaction", "world-restore"] where FileManager.default.fileExists(atPath: paths.gameDataState(instance.id).appendingPathComponent(name).path) {
            throw RuriError.message("实例还有未完成的文件操作，请先恢复后再移动。")
        }
        result.worlds = try InstanceTransfer.lockWorlds(paths.game(instance.id))
        try requireFinishedSessions(paths: paths, instanceID: instance.id)
        return result
    }

    static func requireFinishedSessions(paths: LauncherPaths, instanceID: UUID) throws {
        let root = try LauncherPaths.safePath("sessions", within: paths.instance(instanceID))
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard entries.count <= 100_000 else { throw RuriError.message("运行记录数量过多，请先整理后再移动。") }
        for url in entries where url.lastPathComponent != ".DS_Store" {
            try Task.checkCancellation()
            let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true, let id = UUID(uuidString: url.lastPathComponent) else {
                throw RuriError.message("运行记录目录包含无法确认的项目，请先检查后再移动：\(url.lastPathComponent)")
            }
            let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: id)
            guard record.state.isFinished,
                  record.monitorIdentity.map({ $0.liveness == .exited }) ?? true,
                  record.gameIdentity.map({ $0.liveness == .exited }) ?? true else {
                throw RuriError.message("实例仍有未结束或状态未确认的运行会话，请先检查运行记录，再移动实例。")
            }
        }
    }

    deinit { worlds.forEach { close($0) } }
}
