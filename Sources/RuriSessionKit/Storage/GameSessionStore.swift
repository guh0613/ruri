import Foundation
import Darwin
import RuriLocalization

public enum GameSessionStore {
    public static func directory(paths: any SessionPaths, instanceID: UUID, sessionID: UUID) throws -> URL {
        try SessionFileSystem.safePath("diagnostics/\(sessionID.uuidString)", within: paths.instance(instanceID))
    }
    public static func load(paths: any SessionPaths, instanceID: UUID, sessionID: UUID) throws -> GameSession {
        guard let record = try GameHistoryStore.load(paths: paths, sessionID: sessionID), record.instanceID == instanceID else {
            throw RuriError.message(Messages.SessionUI.recordUnavailable)
        }
        return record
    }
    public static func list(paths: any SessionPaths, instanceID: UUID) throws -> [GameSession] {
        try GameHistoryStore.runtimeRecords(paths: paths, instanceID: instanceID)
    }
    public enum LogSource: Equatable, Sendable { case launcher, console, combined, nativeDebug, fallback }
    package static func selectedFile(paths: any SessionPaths, session: GameSession, source: LogSource) throws -> GameLogFile? {
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
    public static func logTail(paths: any SessionPaths, session: GameSession, byteLimit: Int = 2_097_152, source: LogSource = .combined) throws -> String {
        let eventText = source == .launcher || source == .combined ? try GameSessionEventStore.text(paths: paths, session: session) : ""
        if let file = try selectedFile(paths: paths, session: session, source: source) {
            let handle = try file.openVerified(); defer { try? handle.close() }
            let limit = max(0, min(byteLimit, 2_097_152)), length = file.reference.size
            try handle.seek(toOffset: UInt64(max(0, length - Int64(limit))))
            let data = try handle.read(upToCount: limit) ?? Data()
            let text = GameLogRedactor().redact(String(decoding: data, as: UTF8.self))
            let body = length > limit ? Messages.CoreGameSession.truncatedLog(String(text.drop(while: { $0 != "\n" }).dropFirst())).localized : text
            return source == .combined ? bounded(eventText + body, byteLimit: byteLimit) : body
        }
        if !eventText.isEmpty { return bounded(eventText, byteLimit: byteLimit) }
        return ""
    }
    package static func readTail(_ url: URL, byteLimit: Int) throws -> String {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(.ENOENT) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw RuriError.message(Messages.CoreGameSession.logNotRegularFile) }
        let length = try handle.seekToEnd(), limit = UInt64(max(0, min(byteLimit, 8_388_608)))
        try handle.seek(toOffset: length > limit ? length - limit : 0)
        let data = try handle.read(upToCount: Int(limit)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return length > limit ? Messages.CoreGameSession.truncatedLog(String(text.drop(while: { $0 != "\n" }).dropFirst())).localized : text
    }
    package static func bounded(_ text: String, byteLimit: Int) -> String {
        let data = Data(text.utf8), limit = max(0, byteLimit)
        guard data.count > limit else { return text }
        let tail = data.suffix(limit)
        guard let newline = tail.firstIndex(of: 10) else { return "" }
        return Messages.CoreGameSession.truncatedLog(String(decoding: tail[tail.index(after: newline)...], as: UTF8.self)).localized
    }
}
