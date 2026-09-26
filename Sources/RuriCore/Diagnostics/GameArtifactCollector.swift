import Foundation
import Darwin
import RuriLocalization

/// Capture known files before post-launch commands can replace them.
enum GameArtifactCollector {
    static func preserveSystemReports(_ documents: [GameDiagnosticDocument], paths: LauncherPaths, session: GameSession,
                                      redactor: GameLogRedactor) throws -> [GameSession.Evidence] {
        guard !documents.isEmpty else { return [] }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        let reports = try GameLogSources.safeFile("reports/macos", within: directory)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return try documents.prefix(3).map { document in
            try Task.checkCancellation()
            guard document.kind == .systemReport, document.title == URL(fileURLWithPath: document.title).lastPathComponent,
                  ["ips", "crash"].contains(URL(fileURLWithPath: document.title).pathExtension.lowercased()) else { throw POSIXError(.EINVAL) }
            let relative = "reports/macos/" + document.title
            let destination = try GameLogSources.safeFile(relative, within: directory)
            try Data(redactor.redact(document.text).utf8).write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return .init(relativePath: relative, name: document.title, truncated: document.truncated)
        }
    }

    static func collect(paths: LauncherPaths, session: GameSession, exit: GameExit, redactor: GameLogRedactor) throws -> [GameSession.Evidence] {
        var evidence: [GameSession.Evidence] = []
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        var snapshot = session
        snapshot.exit = exit
        if snapshot.nativeLogs == nil { snapshot.nativeLogs = GameLogSources.references(paths: paths, session: snapshot) }
        let sources = try GameLogSources.native(paths: paths, session: snapshot)
        guard !sources.isEmpty else { return [] }
        let reports = directory.appendingPathComponent("reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var budget = 8 * 1_048_576
        // Crash reports take precedence; latest.log contributes only its tail.
        for (index, source) in sources.prefix(4).enumerated() where budget > 0 {
            do {
                let url = source.url
                let handle = try source.openVerified(); defer { try? handle.close() }
                let limit = min(budget, 2 * 1_048_576), length = try handle.seekToEnd()
                let offset = source.kind == .output && length > limit ? length - UInt64(limit) : 0
                try handle.seek(toOffset: offset)
                var data = try handle.read(upToCount: limit) ?? Data()
                let truncated = length > data.count
                if offset > 0 { if let newline = data.firstIndex(of: 10) { data.removeSubrange(...newline) } else { data.removeAll() } }
                let content = redactor.redact(String(decoding: data, as: UTF8.self))
                let relative = "reports/\(index)-\(url.lastPathComponent)"
                let destination = try LauncherPaths.safePath(relative, within: directory)
                let encoded = Data((content + (truncated ? Messages.CoreGameSession.reportTooLargeNotice.localized : "")).utf8)
                try encoded.prefix(budget).write(to: destination, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                evidence.append(.init(relativePath: relative, name: url.lastPathComponent, truncated: truncated || encoded.count > budget))
                budget -= min(encoded.count, budget)
            } catch {
                // Other evidence is still useful when one file cannot be read.
                continue
            }
        }
        return evidence
    }
}
