import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageLaunch(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (_, paths, downloader) = try await context(request), service = LaunchService(paths: paths, downloader: downloader)
        let id = try uuid(request.operand()), account = try request.string("account").map(uuid)
        if request.spec.path.last == "preflight" || request.dryRun { return try await service.preflight(instanceID: id, accountID: account, worldFolder: request.string("world")) }
        let record = try await service.start(instanceID: id, accountID: account, worldFolder: request.string("world"), progress: { output.progress($0) }, updated: { output.event("session", sessionValue($0)) })
        return sessionValue(record)
    }
    @MainActor static func manageSession(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (_, paths, _) = try await context(request), action = request.spec.path.last!
        if action == "list" {
            let id = try request.string("instance").map(uuid), limit = request.flag("all") ? 500 : (request.integer("limit") ?? 50)
            var offset = request.flag("all") ? 0 : (request.integer("offset") ?? 0), records: [GameSession] = []
            while true {
                let page = try GameHistoryStore.list(paths: paths, query: .init(instanceID: id, search: request.string("search") ?? "", problemsOnly: request.flag("problems"), limit: limit + (request.flag("all") ? 0 : 1), offset: offset))
                records += page
                if !request.flag("all") || page.count < limit { break }; offset += page.count
            }
            return .object(["items": .array((request.flag("all") ? records : Array(records.prefix(limit))).map(sessionValue)), "offset": .integer(request.flag("all") ? 0 : offset), "hasMore": .bool(!request.flag("all") && records.count > limit)])
        }
        let instanceID = try uuid(request.operand()), id = try uuid(request.operand(1))
        let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: id)
        switch action {
        case "show": return sessionValue(record)
        case "wait":
            let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instanceID, sessionID: id)
            return sessionValue(finished)
        case "quit", "stop":
            if !request.dryRun {
                if action == "quit" { _ = try GameMonitorClient.requestNormalQuit(paths: paths, record: record) }
                else { try GameMonitorClient.requestStop(paths: paths, record: record) }
            }
            return .object(["sessionID": .string(id.uuidString), "requested": .string(action), "dryRun": .bool(request.dryRun)])
        case "logs":
            guard !request.flag("follow") || (!request.common.json && request.common.output != "json") else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t28723ddb22d1.localized) }
            let limit = request.integer("lines") ?? 200
            guard (1...10000).contains(limit) else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tafd6142d30ec.localized) }
            let source: GameSessionStore.LogSource = switch request.string("source") { case "preparation": .launcher; case "latest": .console; case "debug": .nativeDebug; default: .fallback }
            let redactor = GameShareRedactor()
            var previous = "", current = record
            repeat {
                try Task.checkCancellation()
                current = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: id)
                let raw = try source == .fallback ? GameMonitorClient.logPreview(paths: paths, session: current) : GameSessionStore.logTail(paths: paths, session: current, byteLimit: 1_048_576, source: source)
                let text = redactor.redact(raw.components(separatedBy: .newlines).suffix(limit).joined(separator: "\n"))
                if !request.flag("follow") { return .object(["sessionID": .string(id.uuidString), "text": .string(text), "bounded": .bool(true)]) }
                if text != previous {
                    let append = text.hasPrefix(previous)
                    output.event("log", .object(["sessionID": .string(id.uuidString), "replacement": .bool(!append), "text": .string(append ? String(text.dropFirst(previous.count)) : text)]))
                    previous = text
                }
                if current.state.isFinished { break }
                guard GameMonitorClient.activity(current) == .monitoring else { throw OperationFailure("SESSION_RECOVERY_REQUIRED", Messages.CLIInterface.t043b9f54ca4c.localized, nextActions: [.init(["recovery", "list", "--json"])]) }
                try await Task.sleep(for: .seconds(1))
            } while true
            return sessionValue(current)
        case "diagnose":
            let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: record, includeGameLogs: true), redactor = GameShareRedactor()
            return .object(["sessionID": .string(id.uuidString), "summary": .string(redactor.redact(diagnosis.summary)), "facts": .array(diagnosis.facts.map { .string(redactor.redact($0)) }),
                "findings": .array(diagnosis.findings.map { finding in .object(["id": .string(finding.id), "title": .string(finding.title), "explanation": .string(redactor.redact(finding.explanation)), "confidence": .string(finding.confidence.rawValue),
                    "steps": .array(finding.steps.map { .string(redactor.redact($0)) }), "actions": .array(finding.actions.map { .string($0.rawValue) }), "evidence": .array(finding.evidence.map { .object(["documentID": .string($0.documentID), "line": .integer($0.line), "excerpt": .string(redactor.redact($0.excerpt))]) })]) }),
                "limitations": .array(diagnosis.limitations.map { .string(redactor.redact($0)) })])
        case "export":
            let file = URL(fileURLWithPath: try request.operand(2)); try requireNewFile(file)
            let bundle = try GameDiagnosticBundle.collect(paths: paths, session: record)
            if !request.dryRun { try bundle.export(selectedIDs: Set(bundle.files.map(\.id)), to: file, paths: paths) }
            return .object(["file": .string(file.path), "dryRun": .bool(request.dryRun), "files": .array(bundle.files.map { .object(["path": .string($0.path), "bytes": .integer($0.byteCount), "redacted": .bool($0.changedByRedaction)]) })])
        default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.te5e3bed93ff1.localized)
        }
    }
    static func sessionValue(_ record: GameSession) -> Value {
        .object(["id": .string(record.id.uuidString), "instanceID": .string(record.instanceID.uuidString), "instanceName": .string(record.instanceName),
            "state": .string(record.state.rawValue), "stage": .string(record.stage.rawValue), "createdAt": .string(record.createdAt.ISO8601Format()),
            "finished": .bool(record.state.isFinished), "playedSeconds": .number(record.playedSeconds), "gameExitCode": record.exit.map { .integer($0.shellStatus) } ?? .null,
            "failure": .text(record.failure), "activity": .string(String(describing: GameMonitorClient.activity(record)))])
    }
}
