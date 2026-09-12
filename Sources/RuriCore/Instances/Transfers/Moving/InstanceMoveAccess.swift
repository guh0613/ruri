import RuriLocalization
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
        try result.lease.excludeLocationOperations()
        for name in [".content-operation.lock", ".world-operation.lock"] {
            let lock = GameDataOperationLock()
            try lock.acquire(directory: paths.gameDataState(instance.id), name: name); result.operations.append(lock)
        }
        for name in ["content-transaction", "world-restore"] where FileManager.default.fileExists(atPath: paths.gameDataState(instance.id).appendingPathComponent(name).path) {
            throw RuriError.message(Messages.CoreInstanceMoveAccess.unfinishedFileOperations)
        }
        result.worlds = try InstanceTransfer.lockWorlds(paths.game(instance.id))
        try requireFinishedSessions(paths: paths, instanceID: instance.id)
        return result
    }

    static func requireFinishedSessions(paths: LauncherPaths, instanceID: UUID) throws {
        let root = try LauncherPaths.safePath("sessions", within: paths.instance(instanceID))
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard entries.count <= 100_000 else { throw RuriError.message(Messages.CoreInstanceMoveAccess.tooManyRunRecords) }
        for url in entries where url.lastPathComponent != ".DS_Store" {
            try Task.checkCancellation()
            let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true, let id = UUID(uuidString: url.lastPathComponent) else {
                throw RuriError.message(Messages.CoreInstanceMoveAccess.unknownRunRecordEntry(url.lastPathComponent))
            }
            let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: id)
            guard record.state.isFinished,
                  record.monitorIdentity.map({ $0.liveness == .exited }) ?? true,
                  record.gameIdentity.map({ $0.liveness == .exited }) ?? true else {
                throw RuriError.message(Messages.CoreInstanceMoveAccess.unfinishedOrUnconfirmedSession)
            }
        }
    }

    deinit { worlds.forEach { close($0) } }
}
