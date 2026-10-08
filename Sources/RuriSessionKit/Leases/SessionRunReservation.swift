import Foundation
import RuriLocalization

/// The on-disk v1 reservation also remains readable by an already-running client.
package struct SessionRunReservation: Codable {
    package let version: Int
    package let paths: SessionLocationSnapshot
    package let instanceID: UUID
    package let sessionID: UUID
    package init(paths: SessionLocationSnapshot, instanceID: UUID, sessionID: UUID) {
        version = 1; self.paths = paths; self.instanceID = instanceID; self.sessionID = sessionID
    }
    package static func load(in root: URL) throws -> Self? {
        let file = try SessionFileSystem.safePath(".ruri/active-run.json", within: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let record = try JSONDecoder().decode(Self.self, from: SessionFileSystem.readBounded(file, limit: 131_072))
        guard record.version == 1 else { throw RuriError.message(Messages.CoreSharedGameDirectoryLease.reservationMismatch) }
        return record
    }
    package func save(in root: URL) throws {
        let file = try SessionFileSystem.safePath(".ruri/active-run.json", within: root)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
    package static func clear(session: GameSession, in root: URL) throws {
        guard session.state.isFinished, let record = try load(in: root),
              record.instanceID == session.instanceID, record.sessionID == session.id else { return }
        try FileManager.default.removeItem(at: SessionFileSystem.safePath(".ruri/active-run.json", within: root))
    }
}
