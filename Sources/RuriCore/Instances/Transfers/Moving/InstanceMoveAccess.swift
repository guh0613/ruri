import RuriLocalization
import Foundation
import Darwin

/// History stays in the database when instance files move. Validate that no
/// database record describes an unfinished/unconfirmed writer.
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
        func requireFinished(_ record: GameSession) throws {
            guard record.state.isFinished,
                  record.monitorIdentity.map({ $0.liveness == .exited }) ?? true,
                  record.gameIdentity.map({ $0.liveness == .exited }) ?? true else {
                throw RuriError.message(Messages.CoreInstanceMoveAccess.unfinishedOrUnconfirmedSession)
            }
        }
        var offset = 0
        while true {
            let records = try GameHistoryStore.list(paths: paths, query: .init(instanceID: instanceID, limit: 500, offset: offset))
            for record in records { try requireFinished(record) }
            if records.count < 500 { break }
            offset += records.count
        }
    }

    deinit { worlds.forEach { close($0) } }
}
