import Foundation
import Darwin
import RuriLocalization

public enum GameSessionStore {
    public static func directory(paths: LauncherPaths, instanceID: UUID, sessionID: UUID) throws -> URL {
        try LauncherPaths.safePath("diagnostics/\(sessionID.uuidString)", within: paths.instance(instanceID))
    }
    public static func load(paths: LauncherPaths, instanceID: UUID, sessionID: UUID) throws -> GameSession {
        guard let record = try GameHistoryStore.load(paths: paths, sessionID: sessionID), record.instanceID == instanceID else {
            throw RuriError.message(Messages.SessionUI.recordUnavailable)
        }
        return record
    }
    public static func list(paths: LauncherPaths, instanceID: UUID) throws -> [GameSession] {
        try GameHistoryStore.runtimeRecords(paths: paths, instanceID: instanceID)
    }
    public enum LogSource: Equatable, Sendable { case launcher, console, combined, nativeDebug, fallback }
    static func selectedFile(paths: LauncherPaths, session: GameSession, source: LogSource) throws -> GameLogFile? {
        if source == .launcher { return nil }
        if source != .fallback {
            let name = source == .nativeDebug ? "logs/debug.log" : "logs/latest.log"
            if let native = try GameLogSources.native(paths: paths, session: session, only: name).first { return native }
            let title = source == .nativeDebug ? "debug.log" : "latest.log"
            let saved = try GameLogSources.saved(paths: paths, session: session)
            if let evidence = session.evidence.first(where: { $0.name == title }), let file = saved.first(where: { $0.reference.relativePath == evidence.relativePath }) { return file }
            if source == .nativeDebug { return nil }
        }
        let saved = try GameLogSources.saved(paths: paths, session: session)
        return saved.first { $0.reference.relativePath == "console-tail.log" } ?? saved.first { $0.reference.relativePath == "console.log" }
    }
    public static func logTail(paths: LauncherPaths, session: GameSession, byteLimit: Int = 2_097_152, source: LogSource = .combined) throws -> String {
        let eventText = source == .launcher || source == .combined ? try GameSessionEventStore.text(paths: paths, session: session) : ""
        if let file = try selectedFile(paths: paths, session: session, source: source) {
            let handle = try file.openVerified(); defer { try? handle.close() }
            let limit = max(0, min(byteLimit, 2_097_152)), length = file.reference.size
            try handle.seek(toOffset: UInt64(max(0, length - Int64(limit))))
            let data = try handle.read(upToCount: limit) ?? Data()
            let text = GameLogRedactor().redact(String(decoding: data, as: UTF8.self))
            let body = length > limit ? Messages.CoreGameSession.truncatedLogNotice.localized + String(text.drop(while: { $0 != "\n" }).dropFirst()) : text
            return source == .combined ? bounded(eventText + body, byteLimit: byteLimit) : body
        }
        if !eventText.isEmpty { return bounded(eventText, byteLimit: byteLimit) }
        return ""
    }
    static func readTail(_ url: URL, byteLimit: Int) throws -> String {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(.ENOENT) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw RuriError.message(Messages.CoreGameSession.logNotRegularFile) }
        let length = try handle.seekToEnd(), limit = UInt64(max(0, min(byteLimit, 8_388_608)))
        try handle.seek(toOffset: length > limit ? length - limit : 0)
        let data = try handle.read(upToCount: Int(limit)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return length > limit ? Messages.CoreGameSession.truncatedLogNotice.localized + String(text.drop(while: { $0 != "\n" }).dropFirst()) : text
    }
    static func bounded(_ text: String, byteLimit: Int) -> String {
        let data = Data(text.utf8), limit = max(0, byteLimit)
        guard data.count > limit else { return text }
        let tail = data.suffix(limit)
        guard let newline = tail.firstIndex(of: 10) else { return "" }
        return Messages.CoreGameSession.truncatedLogNotice.localized + String(decoding: tail[tail.index(after: newline)...], as: UTF8.self)
    }
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
