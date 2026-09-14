import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func refreshSessions(useCache: Bool = false) async {
        await synchronizeExternalState()
        let ids = state.instances.map(\.id), paths = paths
        let cached = useCache ? Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }) : [:]
        let previousIDs = Set(sessions.map(\.id))
        let result = await Task.detached(priority: .utility) {
            var records: [GameSession] = [], failures: [UUID: String] = [:], pending = Set<UUID>(), instanceCopies = Set<UUID>(), instanceMoves = Set<UUID>()
            for id in ids {
                do { records += try GameSessionStore.list(paths: paths, instanceID: id, cached: cached) } catch { failures[id] = error.localizedDescription }
                if RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: id) { pending.insert(id) }
                if InstanceCopyGuard.hasPending(paths: paths, instanceID: id) { instanceCopies.insert(id) }
                if InstanceMoveGuard.hasPending(paths: paths, instanceID: id) { instanceMoves.insert(id) }
            }
            return (records, failures, pending, instanceCopies, instanceMoves)
        }.value
        var merged = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let loadedIDs = Set(result.0.map(\.id))
        for record in result.0 where (merged[record.id]?.updatedAt ?? .distantPast) <= record.updatedAt { merged[record.id] = record }
        // Keep launches added while the read yielded; discard pruned history.
        let updated = merged.values.filter { ids.contains($0.instanceID) && (!previousIDs.contains($0.id) || loadedIDs.contains($0.id) || result.1[$0.instanceID] != nil) }.sorted { $0.createdAt > $1.createdAt }
        if sessions != updated { sessions = updated }
        if pendingDirectoryCopyIDs != result.2 { pendingDirectoryCopyIDs = result.2 }
        if pendingInstanceCopyIDs != result.3 { pendingInstanceCopyIDs = result.3 }
        if pendingInstanceMoveIDs != result.4 { pendingInstanceMoveIDs = result.4 }
        let failures = Set(result.1.keys)
        if failures != failedSessionReadIDs, let message = result.1.values.first { report(Messages.AppAppModelSessions.historyReadWarning(message), level: .warning) }
        failedSessionReadIDs = failures
    }
    func publishSession(_ record: GameSession) {
        if let index = sessions.firstIndex(where: { $0.id == record.id }) { if sessions[index] != record { sessions[index] = record } }
        else { sessions.insert(record, at: 0) }
    }
}
