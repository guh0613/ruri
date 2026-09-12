import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func refreshSessions() async {
        await synchronizeExternalState()
        let ids = state.instances.map(\.id), paths = paths
        let result = await Task.detached(priority: .utility) {
            var records: [GameSession] = [], failures: [UUID: String] = [:], pending = Set<UUID>(), instanceCopies = Set<UUID>(), instanceMoves = Set<UUID>()
            for id in ids {
                do { records += try GameSessionStore.list(paths: paths, instanceID: id) } catch { failures[id] = error.localizedDescription }
                if RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: id) { pending.insert(id) }
                if InstanceCopyGuard.hasPending(paths: paths, instanceID: id) { instanceCopies.insert(id) }
                if InstanceMoveGuard.hasPending(paths: paths, instanceID: id) { instanceMoves.insert(id) }
            }
            return (records, failures, pending, instanceCopies, instanceMoves)
        }.value
        for record in result.0 {
            if let current = sessions.first(where: { $0.id == record.id }), current.updatedAt > record.updatedAt { continue }
            publishSession(record)
        }
        if pendingDirectoryCopyIDs != result.2 { pendingDirectoryCopyIDs = result.2 }
        if pendingInstanceCopyIDs != result.3 { pendingInstanceCopyIDs = result.3 }
        if pendingInstanceMoveIDs != result.4 { pendingInstanceMoveIDs = result.4 }
        let failures = Set(result.1.keys)
        if failures != failedSessionReadIDs, let message = result.1.values.first { notice = Messages.AppAppModelSessions.historyReadWarning(message).localized }
        failedSessionReadIDs = failures
        sessions.removeAll { !ids.contains($0.instanceID) }
        sessions.sort { $0.createdAt > $1.createdAt }
    }
    func publishSession(_ record: GameSession) {
        if let index = sessions.firstIndex(where: { $0.id == record.id }) { if sessions[index] != record { sessions[index] = record } }
        else { sessions.insert(record, at: 0) }
    }
}
