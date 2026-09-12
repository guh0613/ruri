import RuriLocalization
import Foundation

public struct GameSession: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case preparing, running, succeeded, stopped, failed, cancelled, interrupted
        public var isFinished: Bool { self != .preparing && self != .running }
    }
    public enum Stage: String, Codable, Sendable {
        case preparing, installation, recovery, account, manifest, java, arguments, beforeCommand, starting, running, quitting, stopping, afterCommand, finished, monitorRecovery
        public var title: String { message.localized }
        public var message: LocalizedMessage {
            switch self {
            case .preparing: Messages.CoreGameSession.preparingLaunch
            case .installation: Messages.CoreGameSession.installingGame
            case .recovery: Messages.CoreGameSession.checkingInstance
            case .account: Messages.CoreGameSession.validatingAccount
            case .manifest: Messages.CoreGameSession.readingVersion
            case .java: Messages.CoreGameSession.preparingJava
            case .arguments: Messages.CoreGameSession.buildingLaunchArguments
            case .beforeCommand: Messages.CoreGameSession.runningBeforeCommand
            case .afterCommand: Messages.CoreGameSession.runningAfterCommand
            case .starting: Messages.CoreGameSession.startingGameProcess
            case .running: Messages.CoreGameSession.gameProcessRunning
            case .stopping: Messages.CoreGameSession.requestingGameExit
            case .quitting: Messages.CoreGameSession.waitingForGameExit
            case .finished: Messages.CoreGameSession.gameExited
            case .monitorRecovery: Messages.CoreGameSession.recoveringInterruptedRecord
            }
        }
    }
    public struct Event: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let date: Date
        public let stage: Stage
        public let message: String
        public var localizedMessage: LocalizedMessage? = nil
        public var displayMessage: String { localizedMessage?.localized ?? message }
    }
    public struct Evidence: Codable, Identifiable, Equatable, Sendable {
        public let relativePath: String
        public let name: String
        public let truncated: Bool
        public var id: String { relativePath }
    }
    public var schema = 1
    public let id: UUID
    public let instanceID: UUID
    public let instanceName: String
    public let gameVersion: String
    public let loader: String
    public let loaderVersion: String?
    public var memoryMB: Int
    public var memory: LaunchMemory?
    public var baselinePlayTime: Double?
    public let operatingSystem: String
    public let hostArchitecture: String
    public let accountMode: String
    public var ownerPID: Int32
    public let createdAt: Date
    public var updatedAt: Date
    public var state: State
    public var stage: Stage
    public var java: String?
    public var processID: Int32?
    public var monitorIdentity: ProcessIdentity?
    public var gameIdentity: ProcessIdentity?
    public var commandIdentity: ProcessIdentity?
    public var commandResults: [GameCommandResult]?
    public var failure: String?
    public var failureMessage: LocalizedMessage? = nil
    public var displayFailure: String? { failureMessage?.localized ?? failure }
    public var exit: GameExit?
    public var interruption: GameSessionInterruption?
    public var nativeQuitSupported: Bool?
    public var normalQuitAttempt: GameNormalQuitAttempt?
    public var events: [Event]
    public var evidence: [Evidence]
    public var title: String {
        if stage == .afterCommand && !state.isFinished { return Messages.CoreGameSession.runningAfterCommandAfterExit.localized }
        if let command = commandResults?.last, command.phase == .after, !command.succeeded, state.isFinished { return (exit?.summary ?? Messages.CoreGameSession.gameExited.localized) + " · " + command.summary }
        if let exit { return exit.summary }
        switch state {
        case .preparing: return Messages.CoreGameSession.startedWithoutCompletion(stage.title).localized
        case .running: return Messages.CoreGameSession.startedWithoutExitRecord.localized
        case .cancelled: return Messages.CoreGameSession.launchCancelled.localized
        case .failed: return Messages.CoreGameSession.phaseFailed(stage.title).localized
        case .interrupted: return Messages.CoreGameSession.monitoringFinishedUnknownExit.localized
        default: return Messages.CoreGameSession.runFinished.localized
        }
    }
}

/// Credentials are never serialized with a session. Additional masking covers
/// common authentication fields in errors and copied game reports.
public struct GameLogRedactor: Sendable {
    private var secrets: [String] = []
    private static let patterns = [
        #"(?i)(--(?:accessToken|session|clientId|xuid)(?:=|\s+))(?:"[^"\r\n]*(?:"|(?=\r|\n|$))|'[^'\r\n]*(?:'|(?=\r|\n|$))|[^\s,]+)"#,
        #"(?i)("(?:access_token|refresh_token|client_secret|accessToken)"\s*:\s*")[^"]*"#,
        #"(?i)([?&](?:access_token|refresh_token|client_secret|token)=)[^&#\s]+"#,
        #"(?i)(Authorization\s*:\s*Bearer\s+)[^\s]+"#
    ].map { try! NSRegularExpression(pattern: $0) }
    public init() {}
    public mutating func addSecrets(_ values: [String]) { secrets = Array(Set(secrets + values.filter { $0.count > 3 })).sorted { $0.count > $1.count } }
    public func redact(_ input: String) -> String {
        var result = input
        for secret in secrets { result = result.replacingOccurrences(of: secret, with: "<redacted>") }
        for pattern in Self.patterns {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1<redacted>")
        }
        return result
    }
}

public enum GameSessionStore {
    public static func directory(paths: LauncherPaths, instanceID: UUID, sessionID: UUID) throws -> URL {
        try LauncherPaths.safePath("sessions/\(sessionID.uuidString)", within: paths.instance(instanceID))
    }
    public static func load(paths: LauncherPaths, instanceID: UUID, sessionID: UUID) throws -> GameSession {
        let directory = try directory(paths: paths, instanceID: instanceID, sessionID: sessionID)
        let url = try LauncherPaths.safePath("session.json", within: directory)
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, (attributes.fileSize ?? .max) <= 1_048_576 else { throw RuriError.message(Messages.CoreGameSession.invalidRunRecordFile) }
        let record = try JSONDecoder().decode(GameSession.self, from: Data(contentsOf: url))
        guard record.schema == 1, record.id == sessionID, record.instanceID == instanceID,
              record.events.count <= 512, record.evidence.count <= 100, record.instanceName.count <= 1024,
              (record.failure?.count ?? 0) <= 32768 else { throw RuriError.message(Messages.CoreGameSession.invalidRunRecordFormat) }
        for evidence in record.evidence {
            guard evidence.relativePath.hasPrefix("reports/"), evidence.name.count <= 1024 else { throw RuriError.message(Messages.CoreGameSession.invalidRunReportPath) }
            _ = try LauncherPaths.safePath(evidence.relativePath, within: directory)
        }
        if let interruption = record.interruption {
            guard interruption.explanation.count <= 8192, record.state == .interrupted, record.exit == nil else { throw RuriError.message(Messages.CoreGameSession.invalidRecoveryRecord) }
        }
        return record
    }
    public static func list(paths: LauncherPaths, instanceID: UUID) throws -> [GameSession] {
        let root = try LauncherPaths.safePath("sessions", within: paths.instance(instanceID))
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return try? load(paths: paths, instanceID: instanceID, sessionID: id)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    public static func logURL(paths: LauncherPaths, session: GameSession) throws -> URL {
        try LauncherPaths.safePath("launcher.log", within: directory(paths: paths, instanceID: session.instanceID, sessionID: session.id))
    }
    public static func logTail(paths: LauncherPaths, session: GameSession, byteLimit: Int = 2_097_152) throws -> String {
        let url = try logURL(paths: paths, session: session)
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw RuriError.message(Messages.CoreGameSession.logNotRegularFile) }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let length = try handle.seekToEnd(), limit = UInt64(max(0, min(byteLimit, 8_388_608)))
        try handle.seek(toOffset: length > limit ? length - limit : 0)
        let data = try handle.read(upToCount: Int(limit)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        return length > limit ? Messages.CoreGameSession.truncatedLogNotice.localized + String(text.drop(while: { $0 != "\n" }).dropFirst()) : text
    }
    public static func exportLog(paths: LauncherPaths, session: GameSession, to destination: URL) throws {
        let source = try logURL(paths: paths, session: session)
        let instanceRoot = paths.instance(session.instanceID).resolvingSymlinksInPath().path + "/sessions/"
        guard destination.isFileURL, !destination.resolvingSymlinksInPath().path.hasPrefix(instanceRoot) else { throw RuriError.message(Messages.CoreGameSession.exportOutsideRunDirectory) }
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw RuriError.message(Messages.CoreGameSession.logNotRegularFile) }
        let input = try FileHandle(forReadingFrom: source); defer { try? input.close() }
        let length = try input.seekToEnd(); try input.seek(toOffset: 0)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".ruri-log-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw RuriError.message(Messages.CoreGameSession.exportFileCreationFailed) }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary); defer { try? output.close() }
        var copied: UInt64 = 0
        while copied < length {
            let data = try input.read(upToCount: Int(min(65_536, length - copied))) ?? Data()
            guard !data.isEmpty else { throw RuriError.message(Messages.CoreGameSession.logChangedDuringExport) }
            try output.write(contentsOf: data); copied += UInt64(data.count)
        }
        try output.synchronize(); try output.close()
        guard rename(temporary.path, destination.path) == 0 else { throw RuriError.message(Messages.CoreGameSession.exportLogSaveFailed) }
    }
}

public enum GameSessionReviewStore {
    public static func mark(_ record: GameSession, paths: LauncherPaths, at date: Date = Date()) throws {
        let location = try InstanceLocationLease.acquire(paths: paths, instanceID: record.instanceID)
        defer { withExtendedLifetime(location) {} }
        guard record.state.isFinished || (record.monitorIdentity != nil && GameMonitorClient.activity(record) != .monitoring) else { return }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        try Data(String(date.timeIntervalSince1970).utf8).write(to: directory.appendingPathComponent("reviewed"), options: .atomic)
    }
    public static func contains(_ record: GameSession, paths: LauncherPaths) throws -> Bool {
        let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        let file = try LauncherPaths.safePath("reviewed", within: directory)
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, (attributes.fileSize ?? .max) <= 1024 else { throw RuriError.message(Messages.CoreGameSession.invalidRunRecordReadMarker) }
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        let date = Double(text).map { Date(timeIntervalSince1970: $0) } ?? ISO8601DateFormatter().date(from: text)
        return date.map { $0 >= record.updatedAt } ?? false
    }
}

@MainActor public final class GameSessionRecorder {
    public private(set) var record: GameSession
    public let directory: URL
    private let paths: LauncherPaths
    private var log: FileHandle?
    private var redactor = GameLogRedactor()
    private var lease: GameRunLease?
    public init(paths: LauncherPaths, instance: GameInstance, accountMode: String) throws {
        // Invalid preferences must still get a preparation-failure record.
        // Launch validation happens after this record exists; no game process
        // can start until the argument builder has produced a valid plan.
        let instance = (try? instance.resolvingPersistedLaunchSettings(paths: paths)) ?? instance
        let memory = try? JVMHeapArguments.resolve(base: instance.frozenMemory ?? MemorySettings(maximumMB: instance.memoryMB).resolve(), arguments: ArgumentTokenizer.split(instance.extraJVMArguments))
        self.paths = paths
        try paths.validateBinding(instance)
        lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        let now = Date(), id = UUID()
        record = GameSession(id: id, instanceID: instance.id, instanceName: instance.name, gameVersion: instance.gameVersion, loader: instance.loader.rawValue,
                             loaderVersion: instance.loaderVersion, memoryMB: memory?.maximumMB ?? instance.memoryMB, baselinePlayTime: instance.playTime, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                             hostArchitecture: JavaRuntime.hostArchitecture, accountMode: accountMode, ownerPID: ProcessInfo.processInfo.processIdentifier,
                             createdAt: now, updatedAt: now, state: .preparing, stage: .preparing, events: [], evidence: [])
        record.memory = memory
        directory = try GameSessionStore.directory(paths: paths, instanceID: instance.id, sessionID: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let logURL = directory.appendingPathComponent("launcher.log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw RuriError.message(Messages.CoreGameSession.runLogCreationFailed) }
        log = try FileHandle(forWritingTo: logURL)
        try transition(.preparing)
        try lease?.reserve(paths: paths, session: record)
    }
    public init(resuming sessionID: UUID, instanceID: UUID, paths: LauncherPaths, monitor: ProcessIdentity) throws {
        self.paths = paths
        lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID, ignoringSession: sessionID)
        record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
        guard !record.state.isFinished, record.processID == nil, record.monitorIdentity == monitor,
              monitor.pid == ProcessInfo.processInfo.processIdentifier, monitor.isAlive else { throw RuriError.message(Messages.CoreGameSession.monitorCannotAdoptRun) }
        directory = try GameSessionStore.directory(paths: paths, instanceID: instanceID, sessionID: sessionID)
        log = try FileHandle(forWritingTo: GameSessionStore.logURL(paths: paths, session: record)); try log?.seekToEnd()
        record.ownerPID = monitor.pid; record.updatedAt = Date(); try save()
    }
    public func handoff(to monitor: ProcessIdentity) throws {
        guard record.processID == nil, !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.runCannotBeHandedToMonitor) }
        record.monitorIdentity = monitor; record.updatedAt = Date(); try save(); try close()
    }
    public func addSecrets(_ values: [String]) { redactor.addSecrets(values) }
    public func redacted(_ text: String) -> String { redactor.redact(text) }
    public func append(_ text: String) throws {
        guard let log else { throw RuriError.message(Messages.CoreGameSession.runLogClosed) }
        try log.write(contentsOf: Data((redactor.redact(text) + "\n").utf8))
    }
    public func transition(_ stage: GameSession.Stage, message: String? = nil) throws {
        try transition(stage, message: message.map(LocalizedMessage.verbatim) ?? stage.message)
    }
    public func transition(_ stage: GameSession.Stage, message: LocalizedMessage) throws {
        guard !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        record.stage = stage; record.updatedAt = Date()
        let descriptor = message.recorded(redact: redactor.redact)
        record.events.append(.init(id: UUID(), date: record.updatedAt, stage: stage, message: descriptor.fallback, localizedMessage: descriptor))
        try append("[Ruri] \(record.updatedAt.ISO8601Format()) \(descriptor.fallback)")
        try save()
    }
    public func setJava(_ label: String) throws { record.java = label; try save() }
    public func setMemory(_ memory: LaunchMemory) throws {
        guard record.processID == nil, !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.memoryChangeAfterLaunch) }
        record.memory = memory; record.memoryMB = memory.maximumMB; try save()
    }
    public func setNativeQuitSupported(_ supported: Bool) throws { record.nativeQuitSupported = supported; try save() }
    func recordNormalQuit(_ request: GameNormalQuitRequest, accepted: Bool) throws {
        guard !record.state.isFinished else { return }
        let attempt = GameNormalQuitAttempt(requestID: request.id, requestedAt: request.requestedAt, processedAt: Date(), accepted: accepted)
        record.normalQuitAttempt = attempt; record.updatedAt = attempt.processedAt
        if accepted { record.stage = .quitting }
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: attempt.processedAt, stage: record.stage, message: attempt.explanation, localizedMessage: attempt.explanationMessage.recorded(redact: redactor.redact))) }
        try save(); try append("[Ruri] \(attempt.explanation)")
    }
    public func started(processID: Int32) throws {
        record.processID = processID; record.gameIdentity = ProcessIdentity.read(processID)
        record.state = .running; try transition(.running)
    }
    func commandStarted(processID: Int32) throws { record.commandIdentity = ProcessIdentity.read(processID); record.updatedAt = Date(); try save() }
    func commandFinished(_ result: GameCommandResult) throws {
        record.commandResults = (record.commandResults ?? []) + [result]
        record.commandIdentity = nil; record.updatedAt = result.endedAt
        try save(); try append("[Ruri] " + result.summary)
    }
    func recordGameExit(_ exit: GameExit) throws {
        record.exit = exit; record.updatedAt = Date()
        try save()
        try exit.save(paths: paths, instanceID: record.instanceID)
    }
    public func finish(exit: GameExit) throws {
        guard !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        defer { try? close() }
        record.exit = exit; record.updatedAt = Date()
        record.state = exit.stoppedByLauncher ? .stopped : exit.succeeded ? .succeeded : .failed
        record.stage = .finished
        record.events.append(.init(id: UUID(), date: record.updatedAt, stage: .finished, message: exit.summary, localizedMessage: exit.summaryMessage.recorded(redact: redactor.redact)))
        try save()
        try append(exit.logDescription); try append("[Ruri] \(exit.explanation)")
        do { try GamePlaytimeStore.record(record, paths: paths) }
        catch { try append(Messages.CoreGameSession.playtimeSaveFailed(error.localizedDescription).localized) }
        do { try captureReports(exit: exit) }
        catch { try append(Messages.CoreGameSession.reportCopySaveFailed(error.localizedDescription).localized) }
        try save(); try close()
    }
    public func fail(_ error: any Error, cancelled: Bool) throws {
        guard !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        defer { try? close() }
        record.failure = cancelled ? nil : redactor.redact(String(error.localizedDescription.prefix(32768)))
        record.failureMessage = cancelled ? nil : (error as? RuriError)?.localizedMessage?.recorded(limit: 32768, redact: redactor.redact)
        record.state = cancelled ? .cancelled : .failed; record.updatedAt = Date()
        try save()
        if log != nil { try append("[Ruri] \(cancelled ? Messages.CoreGameSession.launchCancelled.localized : record.failure ?? Messages.CoreGameSession.launchFailed.localized)") }
        try close()
    }
    public func close() throws {
        defer { log = nil; lease = nil }
        try lease?.clearReservation(session: record)
        try log?.synchronize(); try log?.close()
    }
    private func save() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
    }
    private func captureReports(exit: GameExit) throws {
        let game = paths.game(record.instanceID)
        var sources = GameCrashReport.find(in: game, exit: exit).map { $0.url }
        if let latest = try? LauncherPaths.safePath("logs/latest.log", within: game),
           let attributes = try? latest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
           attributes.isRegularFile == true, attributes.isSymbolicLink == false,
           let date = attributes.contentModificationDate, date >= exit.startedAt, date <= exit.endedAt.addingTimeInterval(5) { sources.append(latest) }
        let reports = directory.appendingPathComponent("reports")
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        for (index, url) in sources.prefix(100).enumerated() {
            do {
                let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                let data = try handle.read(upToCount: 8_388_609) ?? Data()
                let truncated = data.count > 8_388_608
                let content = redactor.redact(String(decoding: data.prefix(8_388_608), as: UTF8.self))
                let relative = "reports/\(index)-\(url.lastPathComponent)"
                let destination = try LauncherPaths.safePath(relative, within: directory)
                try (content + (truncated ? Messages.CoreGameSession.reportTooLargeNotice.localized : "")).write(to: destination, atomically: true, encoding: .utf8)
                record.evidence.append(.init(relativePath: relative, name: url.lastPathComponent, truncated: truncated))
            } catch { try append(Messages.CoreGameSession.reportCopyFailed(url.lastPathComponent, error.localizedDescription).localized) }
        }
    }
}
