import Foundation
import Darwin
import RuriLocalization

extension GameSessionStore {
    /// Save exactly the visible snapshot, with share-level privacy masking. Do
    /// not re-open a changing live log after the user has reviewed the preview.
    public static func exportPreview(_ text: String, paths: LauncherPaths, session: GameSession, to destination: URL) throws {
        try validateExportDestination(destination, paths: paths, session: session)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".ruri-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw POSIXError(.EIO) }
        let output = try FileHandle(forWritingTo: temporary); defer { try? output.close() }
        try output.write(contentsOf: Data(GameShareRedactor().redact(text).utf8))
        try output.synchronize(); try output.close()
        guard rename(temporary.path, destination.path) == 0 else { throw POSIXError(.EIO) }
    }

    public static func exportLog(paths: LauncherPaths, session: GameSession, to destination: URL) throws {
        try validateExportDestination(destination, paths: paths, session: session)
        if let file = try selectedFile(paths: paths, session: session, source: .console) {
            let snapshot = try GameLogSnapshot.capture(file, redactor: GameShareRedactor())
            try snapshot.export(to: destination)
        } else {
            let text = !session.state.isFinished && session.controlEndpoint != nil
                ? try GameMonitorClient.logPreview(paths: paths, session: session)
                : try logTail(paths: paths, session: session, source: .launcher)
            try exportPreview(text, paths: paths, session: session, to: destination)
        }
    }
    static func validateExportDestination(_ destination: URL, paths: LauncherPaths, session: GameSession) throws {
        guard destination.isFileURL else { throw POSIXError(.EINVAL) }
        let target = destination.resolvingSymlinksInPath().standardizedFileURL.path
        for root in [paths.root, paths.instance(session.instanceID), GameLogSources.root(paths: paths, session: session)] + paths.directories.map(\.url) + (paths.instanceCustomDirectories?.values.map(\.url) ?? []) {
            let base = root.resolvingSymlinksInPath().standardizedFileURL.path
            guard target != base, !target.hasPrefix(base + "/") else { throw RuriError.message(Messages.CoreGameSession.exportOutsideRunDirectory) }
        }
    }

}

public enum GameSessionReviewStore {
    public static func mark(_ record: GameSession, paths: LauncherPaths, at date: Date = Date()) throws {
        guard record.state.isFinished || (record.monitorIdentity != nil && GameMonitorClient.activity(record) != .monitoring) else { return }
        try GameHistoryStore.withDatabase(paths: paths) { db in
            try db.execute("UPDATE sessions SET reviewed_revision=?, reviewed_at=? WHERE id=? AND revision=? AND updated<=?",
                           [.integer(Int(clamping: record.revision)), .real(date.timeIntervalSince1970), .text(record.id.uuidString),
                            .integer(Int(clamping: record.revision)), .real(date.timeIntervalSince1970)])
        }
    }
    public static func contains(_ record: GameSession, paths: LauncherPaths) throws -> Bool {
        let saved = try GameHistoryStore.withDatabase(paths: paths) { db in
            try db.scalar("SELECT count(*) FROM sessions WHERE id=? AND reviewed_revision=? AND reviewed_at>=?",
                          [.text(record.id.uuidString), .integer(Int(clamping: record.revision)), .real(record.updatedAt.timeIntervalSince1970)]) > 0
        }
        return saved
    }
}
