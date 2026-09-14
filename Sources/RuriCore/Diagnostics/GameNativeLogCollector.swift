import Foundation
import Darwin
import RuriLocalization

/// Explicit collection only. Read bounded snapshots of known game log paths;
/// never copy files into session storage or take paths from log contents.
enum GameNativeLogCollector {
    struct Snapshot {
        var documents: [GameDiagnosticDocument] = []
        var limitations: [String] = []
        var names: Set<String> = []
    }

    static func collect(paths: LauncherPaths, session: GameSession, budget: inout Int) throws -> Snapshot {
        var snapshot = Snapshot()
        var remaining = budget
        guard let started = session.exit?.startedAt ?? session.gameIdentity.map({ Date(timeIntervalSince1970: Double($0.startSeconds) + Double($0.startMicroseconds) / 1_000_000) }) else {
            snapshot.limitations.append(Messages.NativeGameLogs.gameNotStarted.localized)
            return snapshot
        }
        let ended = session.exit?.endedAt ?? session.interruption?.observedAt ?? Date()
        let game = paths.game(session.instanceID).standardizedFileURL.resolvingSymlinksInPath()
        if try hasLaterRun(paths: paths, game: game, session: session) {
            snapshot.limitations.append(Messages.NativeGameLogs.replacedByLaterRun.localized)
            return snapshot
        }
        let exit = session.exit ?? GameExit(status: 0, reason: .exit, processID: session.gameIdentity?.pid ?? 0, startedAt: started, endedAt: ended, stopRequested: false)
        let reports = GameCrashReport.find(in: game, exit: exit)
        var sources: [(String, GameDiagnosticDocument.Kind)] = [("logs/latest.log", .output)]
        sources += reports.prefix(4).map { ($0.kind == .jvm ? $0.url.lastPathComponent : "crash-reports/" + $0.url.lastPathComponent, $0.kind == .jvm ? .jvmReport : .gameReport) }
        sources.append(("logs/debug.log", .output))

        for (relative, kind) in sources {
            try Task.checkCancellation()
            do {
                // Reject symlinks, including an intermediate logs/ directory.
                var prefix = game
                var regular = true
                for part in relative.split(separator: "/") {
                    prefix.appendPathComponent(String(part))
                    if (try? prefix.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { regular = false; break }
                }
                guard regular else { snapshot.limitations.append(Messages.NativeGameLogs.unsafeSource(relative).localized); continue }
                let url = try LauncherPaths.safePath(relative, within: game)
                let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
                if fd < 0 {
                    if errno != ENOENT { snapshot.limitations.append(Messages.NativeGameLogs.unreadable(relative).localized) }
                    continue
                }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? handle.close() }
                var before = stat()
                guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG else {
                    snapshot.limitations.append(Messages.NativeGameLogs.unsafeSource(relative).localized); continue
                }
                func belongsToRun(_ info: stat) -> Bool {
                    let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
                    return modified >= started && modified <= ended.addingTimeInterval(5)
                }
                guard belongsToRun(before) else { snapshot.limitations.append(Messages.NativeGameLogs.otherRun(relative).localized); continue }
                guard remaining > 0 else { snapshot.limitations.append(Messages.CoreGameDiagnosis.analysisReadLimit(relative).localized); continue }
                let length = UInt64(max(0, before.st_size))
                let limit = min(remaining, 8 * 1_048_576)
                let partial = length > limit
                let headCount = partial ? limit / 2 : Int(length)
                let head = try handle.read(upToCount: headCount) ?? Data()
                var documents: [GameDiagnosticDocument] = []
                func document(_ data: Data, tail: Bool) -> GameDiagnosticDocument {
                    var data = data
                    if partial {
                        if tail {
                            if let newline = data.firstIndex(of: 10) { data.removeSubrange(...newline) } else { data.removeAll() }
                        } else {
                            if let newline = data.lastIndex(of: 10) { data.removeSubrange(data.index(after: newline)...) } else { data.removeAll() }
                        }
                    }
                    return .init(id: "game/" + relative + (tail ? "#tail" : ""), relativePath: nil,
                                 title: Messages.NativeGameLogs.sourceTitle(relative).localized, kind: kind,
                                 text: String(decoding: data, as: UTF8.self), isTail: tail, truncated: partial, gameRelativePath: relative)
                }
                documents.append(document(head, tail: false))
                var consumed = head.count
                if partial {
                    let tailCount = limit - headCount
                    try handle.seek(toOffset: length - UInt64(tailCount))
                    let tail = try handle.read(upToCount: tailCount) ?? Data()
                    documents.append(document(tail, tail: true)); consumed += tail.count
                }
                var after = stat()
                guard fstat(fd, &after) == 0, after.st_size >= before.st_size, belongsToRun(after) else {
                    snapshot.limitations.append(Messages.NativeGameLogs.changedDuringRead(relative).localized); continue
                }
                remaining -= consumed
                snapshot.documents += documents
                snapshot.names.insert(url.lastPathComponent)
                if partial { snapshot.limitations.append(Messages.CoreGameDiagnosis.boundedTail(relative).localized) }
            } catch is CancellationError { throw CancellationError() }
            catch { snapshot.limitations.append(Messages.NativeGameLogs.unreadable(relative).localized) }
        }
        // A restart during collection must not attribute new output to old history.
        if try hasLaterRun(paths: paths, game: game, session: session) {
            snapshot.documents = []; snapshot.names = []
            snapshot.limitations.append(Messages.NativeGameLogs.replacedByLaterRun.localized)
        } else {
            budget = remaining
            if snapshot.documents.isEmpty { snapshot.limitations.append(Messages.NativeGameLogs.noMatchingLogs.localized) }
        }
        return snapshot
    }

    private static func hasLaterRun(paths: LauncherPaths, game: URL, session: GameSession) throws -> Bool {
        let state = try StateStore.load(paths)
        var ids: Set<UUID> = [session.instanceID]
        for instance in state.instances where paths.game(instance.id).standardizedFileURL.resolvingSymlinksInPath().path == game.path { ids.insert(instance.id) }
        for id in ids {
            for other in try GameSessionStore.list(paths: paths, instanceID: id) where other.id != session.id && other.createdAt >= session.createdAt {
                if other.processID != nil || other.gameIdentity != nil { return true }
            }
        }
        return false
    }
}
