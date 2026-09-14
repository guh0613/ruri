import RuriLocalization
import Foundation
import ZIPFoundation

/// A share preview owns immutable, already-redacted bytes. Export never reopens
/// the live log, expands a directory, or consults account/launcher settings.
public struct GameDiagnosticBundle: Sendable {
    public struct File: Identifiable, Sendable {
        public let id: String
        public let path: String
        public let title: String
        public let text: String
        public let changedByRedaction: Bool
        public var byteCount: Int { text.utf8.count }
    }
    public let sessionID: UUID
    public let createdAt: Date
    public let files: [File]

    public static func preview(session: GameSession, diagnosis: GameDiagnosis, additionalPrivateText: [String] = [], homeDirectory: String = NSHomeDirectory()) throws -> Self {
        guard session.id == diagnosis.sessionID else { throw RuriError.message(Messages.CoreGameDiagnosticBundle.diagnosticRunMismatch) }
        let redactor = GameShareRedactor(additionalPrivateText: additionalPrivateText, homeDirectory: homeDirectory)
        var files: [File] = []
        func append(id: String, path: String, title: String, text: String) {
            let redacted = redactor.redact(text)
            files.append(.init(id: id, path: path, title: title, text: redacted, changedByRedaction: redacted != text))
        }
        var summary = Messages.CoreGameDiagnosticBundle.diagnosticReportHeader(String(describing: session.createdAt.ISO8601Format()), diagnosis.title, diagnosis.summary).localized
        for finding in diagnosis.findings {
            summary += "\n\(finding.title)（\(finding.confidence.title)）\n\(finding.explanation)\n"
            for (index, step) in finding.steps.enumerated() { summary += "\(index + 1). \(step)\n" }
            // Excerpts are intentionally separate selectable files. Deselecting
            // a log must also remove its quoted contents from the package.
        }
        summary += Messages.CoreGameDiagnosticBundle.readScopeHeader.localized + (diagnosis.limitations.isEmpty ? Messages.CoreGameDiagnosticBundle.noReadErrors.localized : diagnosis.limitations.joined(separator: "\n"))
        append(id: "summary", path: "diagnosis.txt", title: Messages.CoreGameDiagnosticBundle.diagnosticConclusionHeader.localized, text: summary + "\n")
        var environment = Messages.CoreGameDiagnosticBundle.environment(
            session.gameVersion,
            session.loader,
            session.loaderVersion ?? "",
            session.java ?? Messages.CoreGameDiagnosticBundle.environmentUnrecorded.localized,
            session.memory?.summary ?? Messages.CoreGameDiagnosticBundle.heapLimit(String(session.memoryMB)).localized,
            session.operatingSystem,
            session.hostArchitecture,
            session.accountMode,
            session.createdAt.ISO8601Format(),
            session.stage.title,
            session.state.rawValue,
            session.exit?.reason.rawValue ?? Messages.CoreGameDiagnosticBundle.environmentUnrecorded.localized,
            session.exit.map { String($0.status) } ?? Messages.CoreGameDiagnosticBundle.environmentUnrecorded.localized,
            session.exit.map { $0.stopRequested ? Messages.CoreGameDiagnosticBundle.yes.localized : Messages.CoreGameDiagnosticBundle.no.localized } ?? Messages.CoreGameDiagnosticBundle.environmentUnrecorded.localized,
            session.exit?.normalQuitRequested == true ? Messages.CoreGameDiagnosticBundle.yes.localized : session.normalQuitAttempt?.accepted == true ? Messages.CoreGameDiagnosticBundle.exitPending.localized : Messages.CoreGameDiagnosticBundle.environmentUnrecorded.localized).localized
        if let interruption = session.interruption {
            environment += Messages.CoreGameDiagnosticBundle.recoveryEnvironment(interruption.observedAt.ISO8601Format(), interruption.resolution.rawValue, interruption.displayExplanation).localized
        }
        append(id: "environment", path: "environment.txt", title: Messages.CoreGameDiagnosticBundle.gameJavaSystemEnvironment.localized, text: environment + "\n")
        for (index, document) in diagnosis.documents.enumerated() {
            try Task.checkCancellation()
            let stem = document.kind == .output ? "output" : document.kind == .preparation ? "preparation" : document.kind == .jvmReport ? "jvm-report" : "minecraft-report"
            let path: String
            if let relative = document.gameRelativePath {
                guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\"), !relative.contains("\0"),
                      !relative.split(separator: "/").contains("..") else { throw RuriError.message(Messages.CoreGameDiagnosticBundle.invalidReportSelection) }
                path = "game/" + relative + (document.truncated ? (document.isTail ? ".tail.txt" : ".head.txt") : "")
            } else { path = "evidence/\(String(format: "%02d", index + 1))-\(stem)\(document.isTail ? "-tail" : "").txt" }
            let heading = Messages.CoreGameDiagnosticBundle.sourceRangeHeading(document.title, String(describing: document.truncated ? Messages.CoreGameDiagnosticBundle.truncatedFileHeading.localized : Messages.CoreGameDiagnosticBundle.completeFileHeading.localized), String(describing: document.isTail ? Messages.CoreGameDiagnosticBundle.tailLineNumberHeading.localized : Messages.CoreGameDiagnosticBundle.bodyLineNumberHeading.localized)).localized
            let text = document.gameRelativePath != nil && !document.truncated ? document.text : heading + document.text
            append(id: document.id, path: path, title: document.title + (document.truncated ? Messages.CoreGameDiagnosticBundle.excerptHeading.localized : ""), text: text)
        }
        return .init(sessionID: session.id, createdAt: Date(), files: files)
    }

    public func export(selectedIDs: Set<String>, to destination: URL, paths: LauncherPaths) throws {
        let selected = files.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty, selected.count == selectedIDs.count else { throw RuriError.message(Messages.CoreGameDiagnosticBundle.invalidReportSelection) }
        guard destination.isFileURL, destination.pathExtension.lowercased() == "zip" else { throw RuriError.message(Messages.CoreGameDiagnosticBundle.zipSaveLocationSelection) }
        let target = destination.resolvingSymlinksInPath().standardizedFileURL.path
        for url in [paths.root] + paths.directories.map(\.url) {
            let root = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard target != root && !target.hasPrefix(root + "/") else { throw RuriError.message(Messages.CoreGameDiagnosticBundle.diagnosticSaveLocationInvalid) }
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".ruri-diagnostic-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            let archive = try Archive(url: staging, accessMode: .create)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            for file in selected {
                try Task.checkCancellation()
                let data = Data(file.text.utf8)
                try archive.addEntry(with: file.path, type: .file, uncompressedSize: Int64(data.count), modificationDate: createdAt, compressionMethod: .deflate) { position, count in
                    try Task.checkCancellation()
                    return data.subdata(in: Int(position)..<(Int(position) + count))
                }
            }
        }
        try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw RuriError.message(Messages.CoreGameDiagnosticBundle.diagnosticBundleSaveFailed) }
    }
}

public struct GameShareRedactor: Sendable {
    private let additionalPrivateText: [String]
    private let homeDirectory: String
    public init(additionalPrivateText: [String] = [], homeDirectory: String = NSHomeDirectory()) {
        self.additionalPrivateText = additionalPrivateText.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        self.homeDirectory = homeDirectory
    }
    public func redact(_ text: String) -> String {
        var result = text
        if homeDirectory.count > 1 { result = result.replacingOccurrences(of: homeDirectory, with: "<主目录>") }
        for (pattern, replacement) in Self.patterns {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: replacement)
        }
        result = GameLogRedactor().redact(result)
        for value in additionalPrivateText { result = result.replacingOccurrences(of: value, with: "<已隐藏>") }
        return result
    }
    private static let patterns: [(NSRegularExpression, String)] = [
        (#"(?i)(\b(?:access_token|refresh_token|id_token|client_secret|api[_-]?key|accessToken|refreshToken|sessionToken|x-api-key|token)\b["']?\s*[:=]\s*)(?:"[^"\r\n]*(?:"|(?=\r|\n|$))|'[^'\r\n]*(?:'|(?=\r|\n|$))|[^\s"',;}&]+)"#, "$1<凭据>"),
        (#"(?i)(--(?:apiKey|token|accessToken|session|refreshToken|idToken|clientSecret)(?:=|\s+))(?:"[^"\r\n]*(?:"|(?=\r|\n|$))|'[^'\r\n]*(?:'|(?=\r|\n|$))|[^\s,]+)"#, "$1<凭据>"),
        (#"(?i)((?:Authorization|Proxy-Authorization)\s*:\s*)[^\r\n]+"#, "$1<凭据>"),
        (#"(?i)((?:Cookie|Set-Cookie)\s*:\s*)[^\r\n]+"#, "$1<凭据>"),
        (#"\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]+\b"#, "<凭据>"),
        (#"/Users/[^/\r\n"<>]+"#, "/Users/<用户>"),
        (#"(?i)(--(?:username|uuid|xuid|clientId)(?:=|\s+))(?:"[^"\r\n]*(?:"|(?=\r|\n|$))|'[^'\r\n]*(?:'|(?=\r|\n|$))|[^\s,]+)"#, "$1<玩家>"),
        (#"(?i)((?:Setting user|Username)\s*:\s*)[^\r\n]+"#, "$1<玩家>"),
        (#"(?i)("(?:username|displayName|uuid|xuid)"\s*:\s*")[^"]*"#, "$1<玩家>"),
        (#"(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, "<邮箱>"),
        (#"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "<UUID>"),
        (#"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "<IP>"),
        (#"\[(?:[0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F]{0,4}\]"#, "<IP>"),
        (#"(?i)(https?://)[^/\s?#]+"#, "$1<服务地址>"),
        (#"(?i)((?:Connecting to|Connecting to server|连接到)\s+)[^\s,]+"#, "$1<服务器>")
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }
}
