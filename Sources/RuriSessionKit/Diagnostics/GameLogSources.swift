import Foundation
import Darwin
import RuriLocalization

package struct GameLogFile: Sendable {
    package init(url: URL, reference: GameLogReference, kind: GameDiagnosticDocument.Kind, gameRelativePath: String? = nil, truncated: Bool, growing: Bool = false) {
        self.url = url
        self.reference = reference
        self.kind = kind
        self.gameRelativePath = gameRelativePath
        self.truncated = truncated
        self.growing = growing
    }

    package let url: URL
    package let reference: GameLogReference
    package let kind: GameDiagnosticDocument.Kind
    package let gameRelativePath: String?
    package let truncated: Bool
    package var growing = false
    package var id: String { (gameRelativePath == nil ? "saved/" : "game/") + reference.relativePath }
    package var title: String { url.lastPathComponent }

    package func openVerified() throws -> FileHandle {
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
package enum GameLogSources {
    package static func root(paths: any SessionPaths, session: GameSession) -> URL { session.gameDirectory ?? paths.game(session.instanceID) }

    package static func safeFile(_ relative: String, within root: URL) throws -> URL {
        guard GameSession.safeRelativePath(relative) else { throw POSIXError(.EINVAL) }
        var prefix = root
        for part in relative.split(separator: "/") {
            prefix.appendPathComponent(String(part))
            var info = stat()
            if lstat(prefix.path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK { throw POSIXError(.ELOOP) }
        }
        return try SessionFileSystem.safePath(relative, within: root)
    }
    package static func reference(_ relative: String, within root: URL) -> GameLogReference? {
        guard let url = try? safeFile(relative, within: root) else { return nil }
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }; defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return .init(relativePath: relative, info: info)
    }
    package static func baseline(in game: URL) -> [GameLogReference] {
        ["logs/latest.log", "logs/debug.log"].compactMap { reference($0, within: game) }
    }
    package static func references(paths: any SessionPaths, session: GameSession, only: String? = nil) -> [GameLogReference] {
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
    package static func native(paths: any SessionPaths, session: GameSession, only: String? = nil) throws -> [GameLogFile] {
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
    package static func saved(paths: any SessionPaths, session: GameSession) throws -> [GameLogFile] {
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
