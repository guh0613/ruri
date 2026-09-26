import Foundation
import Darwin
import RuriLocalization

/// Bounded collection at exit or on an explicit read. No debugger attach,
/// privileged log access, directory watcher or in-game crash handler is installed.
enum GameSystemReportCollector {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")

    /// macOS writes its report after the process has exited. Only native crash
    /// signals warrant waiting; ordinary Java failures get one immediate read.
    static func collectAfterExit(session: GameSession, root: URL = defaultRoot,
                                 retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]) async throws -> GameEvidenceSnapshot {
        guard let exit = session.exit, exit.requiresAttention else { return .init(documents: [], limitations: []) }
        var snapshot = session
        snapshot.state = .failed
        let retries = exit.reason == .signal && [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP].contains(exit.status) ? retryDelays : []
        for attempt in 0...retries.count {
            try Task.checkCancellation()
            var budget = 6 * 1_048_576
            let result = try collect(session: snapshot, budget: &budget, root: root)
            if !result.documents.isEmpty || attempt == retries.count { return result }
            try await Task.sleep(for: retries[attempt])
        }
        return .init(documents: [], limitations: [])
    }

    static func collect(session: GameSession, budget: inout Int, root: URL = defaultRoot) throws -> GameEvidenceSnapshot {
        guard session.needsAttention, session.hasPlayed, budget > 0 else { return .init(documents: [], limitations: []) }
        let identities = [session.gameIdentity, session.monitorIdentity].compactMap { $0 }
        let pids = Set(identities.map(\.pid) + (session.exit.map { [$0.processID] } ?? []))
        guard !pids.isEmpty else { return .init(documents: [], limitations: []) }
        let started = session.timing?.startedAt ?? session.exit?.startedAt ?? session.createdAt
        let ended = session.exit?.endedAt ?? session.interruption?.observedAt ?? Date()
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)) else {
            return .init(documents: [], limitations: [Messages.SessionRuntime.reportUnavailable.localized])
        }
        let candidates = files.compactMap { file -> (URL, Date)? in
            guard ["ips", "crash"].contains(file.pathExtension.lowercased()),
                  let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified >= started, modified <= ended.addingTimeInterval(120) else { return nil }
            return (file, modified)
        }.sorted { $0.1 > $1.1 }.prefix(32)
        var documents: [GameDiagnosticDocument] = []
        for (file, _) in candidates where budget > 0 && documents.count < 3 {
            try Task.checkCancellation()
            let fd = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { continue }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            // Inspect a small header before spending the report budget on a file.
            guard let header = try? handle.read(upToCount: 65_536) else { continue }
            let prefix = String(decoding: header, as: UTF8.self)
            guard belongs(prefix, pids: pids, ips: file.pathExtension.lowercased() == "ips") else { continue }
            try handle.seek(toOffset: 0)
            let limit = min(budget, 2 * 1_048_576)
            let data = try handle.read(upToCount: limit) ?? Data()
            var after = stat()
            guard fstat(fd, &after) == 0, info.st_size == after.st_size,
                  info.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  info.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { continue }
            budget -= data.count
            var text = String(decoding: data, as: UTF8.self)
            let truncated = info.st_size > data.count
            if !truncated, file.pathExtension.lowercased() == "ips" {
                // IPS has a metadata JSON line followed by the report JSON.
                // A matching header alone can be visible before writing ends.
                guard let newline = text.firstIndex(of: "\n"),
                      (try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8))) is [String: Any] else { continue }
            }
            if truncated, let newline = text.lastIndex(of: "\n") { text = String(text[..<newline]) }
            documents.append(.init(id: "system/" + file.lastPathComponent, relativePath: nil, title: file.lastPathComponent,
                                   kind: .systemReport, text: text, truncated: truncated))
        }
        return .init(documents: documents, limitations: documents.isEmpty ? [Messages.SessionRuntime.reportUnavailable.localized] : [])
    }

    private static func belongs(_ text: String, pids: Set<Int32>, ips: Bool) -> Bool {
        let pattern = ips ? #""procName"\s*:\s*"(?:java|ruri-game|ruri-monitor)""# : #"(?m)^Process:\s+(?:java|ruri-game|ruri-monitor)\s+\[\d+\]"#
        guard text.range(of: pattern, options: .regularExpression) != nil else { return false }
        return pids.contains { pid in
            let pidPattern = ips ? #""pid"\s*:\s*"# + String(pid) + #"\s*[,}]"# : #"(?m)^Process:[^\r\n]*\["# + String(pid) + #"\]"#
            return text.range(of: pidPattern, options: .regularExpression) != nil
        }
    }
}
