import Foundation
import Darwin
import RuriLocalization

/// A reference is not a copy. Finished runs require the same file identity,
/// size and modification time, so a new latest.log can never impersonate it.
public struct GameLogReference: Codable, Equatable, Sendable {
    public let relativePath: String
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64

    init(relativePath: String, info: stat) {
        self.relativePath = relativePath; device = UInt64(UInt32(bitPattern: info.st_dev)); inode = UInt64(info.st_ino)
        size = info.st_size; modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
    }
    var modifiedAt: Date { Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000) }
    func matches(_ info: stat, growing: Bool = false) -> Bool {
        device == UInt64(UInt32(bitPattern: info.st_dev)) && inode == UInt64(info.st_ino) &&
        (growing ? info.st_size >= size : info.st_size == size && Int64(info.st_mtimespec.tv_sec) == modifiedSeconds && Int64(info.st_mtimespec.tv_nsec) == modifiedNanoseconds)
    }
    func validate() throws {
        guard GameSession.safeRelativePath(relativePath), relativePath.utf8.count <= 2048, size >= 0,
              (0..<1_000_000_000).contains(modifiedNanoseconds),
              relativePath == "logs/latest.log" || relativePath == "logs/debug.log" ||
              (relativePath.hasPrefix("crash-reports/crash-") && relativePath.hasSuffix(".txt")) ||
              (relativePath.hasPrefix("hs_err_pid") && relativePath.hasSuffix(".log")) else { throw POSIXError(.EINVAL) }
    }
}

struct GameLogFile: Sendable {
    let url: URL
    let reference: GameLogReference
    let kind: GameDiagnosticDocument.Kind
    let gameRelativePath: String?
    let truncated: Bool
    var growing = false
    var id: String { (gameRelativePath == nil ? "saved/" : "game/") + reference.relativePath }
    var title: String { url.lastPathComponent }

    func openVerified() throws -> FileHandle {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(.ENOENT) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, reference.matches(info, growing: growing) else {
            try? handle.close(); throw RuriError.message(Messages.CoreGameSession.logChangedDuringExport)
        }
        return handle
    }
}

/// Native log metadata is inspected only at launch/exit or on an explicit read.
/// Unknown gzip archives are deliberately not guessed to belong to a session.
enum GameLogSources {
    static func root(paths: LauncherPaths, session: GameSession) -> URL { session.gameDirectory ?? paths.game(session.instanceID) }

    static func safeFile(_ relative: String, within root: URL) throws -> URL {
        guard GameSession.safeRelativePath(relative) else { throw POSIXError(.EINVAL) }
        var prefix = root
        for part in relative.split(separator: "/") {
            prefix.appendPathComponent(String(part))
            var info = stat()
            if lstat(prefix.path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK { throw POSIXError(.ELOOP) }
        }
        return try LauncherPaths.safePath(relative, within: root)
    }
    static func reference(_ relative: String, within root: URL) -> GameLogReference? {
        guard let url = try? safeFile(relative, within: root) else { return nil }
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return .init(relativePath: relative, info: info)
    }
    static func baseline(in game: URL) -> [GameLogReference] {
        ["logs/latest.log", "logs/debug.log"].compactMap { reference($0, within: game) }
    }
    static func references(paths: LauncherPaths, session: GameSession, only: String? = nil) -> [GameLogReference] {
        guard let start = session.exit?.startedAt ?? session.timing?.startedAt ?? session.gameIdentity.map({ Date(timeIntervalSince1970: Double($0.startSeconds) + Double($0.startMicroseconds) / 1_000_000) }) else { return [] }
        let game = root(paths: paths, session: session), end = session.exit?.endedAt ?? session.interruption?.observedAt ?? Date()
        let exit = session.exit ?? GameExit(status: 0, reason: .exit, processID: session.processID ?? 0, startedAt: start, endedAt: end, stopRequested: false)
        let reports = only == nil ? GameCrashReport.find(in: game, exit: exit).prefix(4).map { $0.kind == .jvm ? $0.url.lastPathComponent : "crash-reports/" + $0.url.lastPathComponent } : []
        return (only.map { [$0] } ?? (Array(reports) + ["logs/latest.log", "logs/debug.log"])).compactMap { path in
            guard let value = reference(path, within: game), value.modifiedAt >= start, value.modifiedAt <= end.addingTimeInterval(5),
                  !(session.logBaseline ?? []).contains(value) else { return nil }
            return value
        }
    }
    static func native(paths: LauncherPaths, session: GameSession, only: String? = nil) throws -> [GameLogFile] {
        let game = root(paths: paths, session: session)
        let references = session.nativeLogs ?? references(paths: paths, session: session, only: only)
        return references.compactMap { reference in
            guard only == nil || reference.relativePath == only else { return nil }
            guard let current = self.reference(reference.relativePath, within: game), current == reference,
                  let url = try? safeFile(reference.relativePath, within: game) else { return nil }
            let kind: GameDiagnosticDocument.Kind = reference.relativePath.hasPrefix("hs_err_pid") ? .jvmReport : reference.relativePath.hasPrefix("crash-reports/") ? .gameReport : .output
            return .init(url: url, reference: reference, kind: kind, gameRelativePath: reference.relativePath, truncated: false, growing: session.exit == nil && !session.state.isFinished)
        }
    }
    static func saved(paths: LauncherPaths, session: GameSession) throws -> [GameLogFile] {
        guard session.artifactState != .expired else { return [] }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        var sources = session.evidence.map { ($0.relativePath, $0.truncated) }
        sources += [("console.log", session.outputTruncated == true), ("console-tail.log", session.outputTruncated == true)]
        return sources.compactMap { path, truncated in
            guard let reference = reference(path, within: directory), let url = try? safeFile(path, within: directory) else { return nil }
            let name = url.lastPathComponent
            let kind: GameDiagnosticDocument.Kind = path.hasPrefix("reports/macos/") ? .systemReport : name.contains("hs_err_pid") ? .jvmReport : name.contains("crash-") ? .gameReport : .output
            return .init(url: url, reference: reference, kind: kind, gameRelativePath: nil, truncated: truncated)
        }
    }
}
