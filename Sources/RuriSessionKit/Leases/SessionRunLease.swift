import Foundation
import RuriLocalization

/// Resumes an existing reservation; it cannot authorize a new launch. Core
/// performs global registration/transaction checks while holding these locks
/// before writing the handoff. Every competing operation checks that handoff.
package final class SessionRunLease: Sendable {
    private let location: SessionLocationLease
    private let instance: SessionRunFileLease
    private let shared: SessionRunFileLease?
    private let sharedRoot: URL?

    private init(location: SessionLocationLease, instance: SessionRunFileLease, shared: SessionRunFileLease?, root: URL?) {
        self.location = location; self.instance = instance; self.shared = shared; sharedRoot = root
    }

    package static func resume(paths: SessionLocationSnapshot, instanceID: UUID, sessionID: UUID, monitor: ProcessIdentity) throws -> Self {
        let location = try SessionLocationLease.acquire(paths: paths, instanceID: instanceID, exclusive: false)
        _ = try paths.validated(for: instanceID)
        try SessionOperation.requireNoPending(paths: paths, instanceID: instanceID)
        try requireHandoff(paths: paths, instanceID: instanceID, sessionID: sessionID, monitor: monitor)
        try FileManager.default.createDirectory(at: paths.instance(instanceID), withIntermediateDirectories: true)
        let instance = try SessionRunFileLease.instance(at: paths.instance(instanceID))
        let root = paths.runDirectory(for: instanceID) == .isolated ? nil : paths.game(instanceID)
        let shared = try root.map { try SessionRunFileLease.shared(at: $0) }
        if let root {
            guard let reservation = try SessionRunReservation.load(in: root), reservation.instanceID == instanceID,
                  reservation.sessionID == sessionID else { throw RuriError.message(Messages.CoreSharedGameDirectoryLease.reservationMismatch) }
            let saved = try reservation.paths.validated(for: instanceID)
            guard same(saved.root, paths.root), same(saved.instance(instanceID), paths.instance(instanceID)),
                  same(saved.game(instanceID), root) else { throw RuriError.message(Messages.CoreSharedGameDirectoryLease.reservationMismatch) }
        }
        // Recheck after all kernel locks are held, before allowing any writer.
        try SessionOperation.requireNoPending(paths: paths, instanceID: instanceID)
        try requireHandoff(paths: paths, instanceID: instanceID, sessionID: sessionID, monitor: monitor)
        let records = try GameSessionStore.list(paths: paths, instanceID: instanceID)
        guard !records.contains(where: { $0.id != sessionID && !$0.state.isFinished && $0.monitorActivity != .inactive }) else {
            throw RuriError.message(Messages.CoreGameRunLease.activeRunSession)
        }
        return Self(location: location, instance: instance, shared: shared, root: root)
    }

    package func clearReservation(session: GameSession) throws {
        if let root = sharedRoot { try SessionRunReservation.clear(session: session, in: root) }
    }
    private static func requireHandoff(paths: SessionLocationSnapshot, instanceID: UUID, sessionID: UUID, monitor: ProcessIdentity) throws {
        let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
        guard !record.state.isFinished, record.processID == nil, record.monitorIdentity == monitor,
              monitor.pid == ProcessInfo.processInfo.processIdentifier, monitor.isAlive,
              record.gameDirectory.map({ same($0, paths.game(instanceID)) }) ?? true else {
            throw RuriError.message(Messages.CoreGameSession.monitorCannotAdoptRun)
        }
    }
    private static func same(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL.resolvingSymlinksInPath().path == second.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
