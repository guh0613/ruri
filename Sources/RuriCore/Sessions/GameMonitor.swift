import RuriLocalization
import Foundation
import Darwin

struct MonitorLaunchRequest: Codable {
    static let currentVersion = 1
    let version: Int
    let instanceID: UUID
    let sessionID: UUID
    let monitor: ProcessIdentity
    let plan: LaunchPlan
    let secrets: [String]
    let storage: LauncherPaths
    var language: String? = nil
    var region: String? = nil
}
public enum GameMonitorClient {
    public enum Activity: Equatable, Sendable { case inactive, monitoring, orphaned, uncertain }
    public enum ClientEvent: String, Codable, Sendable { case connected, windowClosed, windowReopened, quitRequested, normalQuitRequested, stopRequested, gameActivationRequested }
    public static func recordEvent(_ event: ClientEvent, paths: LauncherPaths, session: GameSession) throws {
        try GameSessionEventStore.append(event.rawValue, source: "client", sessionID: session.id, paths: paths)
    }
    public static func activity(_ record: GameSession) -> Activity {
        if record.monitorIdentity?.isAlive == true { return .monitoring }
        if record.state.isFinished || record.monitorIdentity == nil { return .inactive }
        if record.monitorIdentity?.liveness == .unverifiable { return .uncertain }
        if record.gameIdentity?.isAlive == true || record.commandIdentity?.isAlive == true { return .orphaned }
        // A monitor may have died between spawning Java and saving its identity.
        if record.gameIdentity == nil || record.gameIdentity?.liveness == .unverifiable { return .uncertain }
        return .inactive
    }
    /// A queued socket update can outlive its monitor. Consult the durable
    /// result before treating an unfinished snapshot as a lost monitor; normal
    /// shutdown commits the final record before the helper exits.
    public static func reconcile(paths: LauncherPaths, record: GameSession) throws -> GameSession {
        guard record.monitorIdentity != nil, !record.state.isFinished, activity(record) != .monitoring else { return record }
        let saved = try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        return saved.isAtLeastAsRecent(as: record) ? saved : record
    }
    public static func helperExecutable() throws -> URL {
        guard let executable = Bundle.main.executableURL else { throw RuriError.message(Messages.CoreGameMonitor.monitorComponentMissing) }
        let parent = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        let candidates = [parent.deletingLastPathComponent().appendingPathComponent("Helpers/ruri-monitor"), parent.appendingPathComponent("ruri-monitor")]
        guard let helper = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw RuriError.message(Messages.CoreGameMonitor.monitorComponentNotFound) }
        return helper
    }
    @MainActor public static func start(plan: LaunchPlan, recorder: GameSessionRecorder, paths: LauncherPaths, secrets: [String], helper: URL? = nil) async throws {
        let secrets = secrets + plan.environmentRedactions
        recorder.addSecrets(secrets)
        try recorder.configureLogging(debug: plan.debugLogging == true)
        if let names = plan.customEnvironmentNames, !names.isEmpty { try recorder.append(Messages.CoreGameMonitor.environmentNames(names.joined(separator: ", ")).localized) }
        if let memory = plan.memory { try recorder.setMemory(memory) }
        let process = Process(), input = Pipe()
        process.executableURL = try helper ?? helperExecutable()
        process.arguments = ["run"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = paths.instance(recorder.record.instanceID)
        try process.run()
        defer { try? input.fileHandleForWriting.close() }
        guard let identity = ProcessIdentity.read(process.processIdentifier) else { throw RuriError.message(Messages.CoreGameMonitor.monitorIdentityFailed) }
        let request = MonitorLaunchRequest(version: MonitorLaunchRequest.currentVersion, instanceID: recorder.record.instanceID, sessionID: recorder.record.id,
                                           monitor: identity, plan: plan, secrets: secrets, storage: paths.monitorSnapshot(for: recorder.record.instanceID),
                                           language: LocalizationContext.current.language, region: LocalizationContext.current.regionIdentifier)
        let data = try JSONEncoder().encode(request)
        guard data.count <= 2_097_152 else { throw RuriError.message(Messages.CoreGameMonitor.launchInfoTooLarge) }
        try Task.checkCancellation()
        try recorder.handoff(to: identity)
        // No launch arguments, access tokens or refresh tokens are written to a
        // transport file or placed on the monitor's own command line.
        try await MonitorBootstrap.send(data, to: input.fileHandleForWriting)
        try input.fileHandleForWriting.close()
        let instanceID = recorder.record.instanceID, sessionID = recorder.record.id
        let accepted = try await Task.detached(priority: .utility) {
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while ContinuousClock.now < deadline {
                let current = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
                if current.state.isFinished || (current.ownerPID == identity.pid && current.controlEndpoint != nil) { return current }
                guard identity.isAlive else { throw RuriError.message(Messages.CoreGameMonitor.monitorInterruptedAtLaunch) }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw RuriError.message(Messages.SessionRuntime.launchTimeout)
        }.value
        recorder.acknowledgeHandoff(accepted)
    }
    public static func requestStop(paths: LauncherPaths, record: GameSession) throws {
        guard !record.state.isFinished, record.monitorIdentity?.isAlive == true else { throw RuriError.message(Messages.CoreGameMonitor.monitorDisconnected) }
        let current = try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        guard current.monitorIdentity == record.monitorIdentity, !current.state.isFinished else { throw RuriError.message(Messages.CoreGameMonitor.sessionChanged) }
        guard current.controlEndpoint != nil else { throw RuriError.message(Messages.CoreGameMonitor.monitorDisconnected) }
        let reply = try MonitorSocket.request(current, command: .stop)
        guard reply.accepted == true else { throw RuriError.message(Messages.CoreGameMonitor.sessionChanged) }
        try? recordEvent(.stopRequested, paths: paths, session: current)
    }
    public static func wait(paths: LauncherPaths, instanceID: UUID, sessionID: UUID) async throws -> GameSession {
        let initial = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
        let observer = FileChangeObserver(directories: [], processes: initial.monitorIdentity.map { [$0.pid] } ?? [], fallbackSeconds: 30)
        defer { observer.cancel() }
        var events = observer.events.makeAsyncIterator()
        while true {
            try Task.checkCancellation()
            let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
            switch activity(record) {
            case .monitoring: _ = await events.next()
            case .orphaned: throw RuriError.message(Messages.CoreGameMonitor.gameStillRunning)
            case .uncertain: throw RuriError.message(Messages.CoreGameMonitor.monitorInterruptedAtLaunch)
            case .inactive: return record
            }
        }
    }
    /// The GUI requests this only when native logs are unavailable or the user
    /// explicitly selects supplemental process output. Transport is memory-only.
    public static func logPreview(paths: LauncherPaths, session: GameSession) throws -> String {
        if !session.state.isFinished, session.controlEndpoint != nil {
            return try MonitorSocket.request(session, command: .snapshot).output?.text ?? ""
        }
        return try GameSessionStore.logTail(paths: paths, session: session, source: .fallback)
    }
}

public enum GameMonitorService {
    @MainActor public static func runFromStandardInput() async -> Int32 {
        // A monitor belongs to the game, not to the terminal or GUI that started it.
        _ = setsid(); _ = signal(SIGHUP, SIG_IGN)
        var request: MonitorLaunchRequest?
        do {
            var data = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= 2_097_152 else { throw RuriError.message(Messages.CoreGameMonitor.requestInfoTooLarge) }
            }
            let decoded = try JSONDecoder().decode(MonitorLaunchRequest.self, from: data)
            request = decoded
            guard decoded.version == MonitorLaunchRequest.currentVersion, decoded.plan.executable.isFileURL,
                  decoded.monitor == ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier) else { throw RuriError.message(Messages.CoreGameMonitor.invalidMonitorRequest) }
            let context = LocalizationContext(language: decoded.language, region: decoded.region ?? Locale.current.identifier)
            return try await LocalizationContext.$current.withValue(context) {
                let paths = try validatedPaths(decoded)
                guard decoded.plan.directory.resolvingSymlinksInPath() == paths.game(decoded.instanceID).resolvingSymlinksInPath() else { throw RuriError.message(Messages.CoreGameMonitor.sessionDirectoryMismatch) }
                let recorder = try GameSessionRecorder(resuming: decoded.sessionID, instanceID: decoded.instanceID, paths: paths, monitor: decoded.monitor)
                recorder.addSecrets(decoded.secrets + decoded.plan.environmentRedactions)
                try recorder.configureLogging(debug: decoded.plan.debugLogging == true)
                return try await GameSessionCoordinator(plan: decoded.plan, recorder: recorder, paths: paths).run()
            }
        } catch {
            if let request {
                LocalizationContext.$current.withValue(LocalizationContext(language: request.language, region: request.region ?? Locale.current.identifier)) {
                    try? recordUnstartedFailure(request, error: error)
                }
            }
            return 1
        }
    }
    @MainActor private static func recordUnstartedFailure(_ request: MonitorLaunchRequest, error: any Error) throws {
        guard request.monitor.pid == ProcessInfo.processInfo.processIdentifier, request.monitor.isAlive else { return }
        let paths = try validatedPaths(request)
        var record = try GameSessionStore.load(paths: paths, instanceID: request.instanceID, sessionID: request.sessionID)
        guard !record.state.isFinished, record.processID == nil, record.monitorIdentity == request.monitor else { return }
        var redactor = GameLogRedactor(); redactor.addSecrets(request.secrets + request.plan.environmentRedactions)
        record.revision = (record.revision) + 1; record.finalSnapshot = true; record.controlEndpoint = nil
        record.state = .failed; record.failure = redactor.redact(String(error.localizedDescription.prefix(32768))); record.updatedAt = Date()
        record.failureMessage = (error as? RuriError)?.localizedMessage?.recorded(limit: 32768, redact: redactor.redact)
        try GameHistoryStore.record(record, paths: paths)
    }
    static func validatedPaths(_ request: MonitorLaunchRequest) throws -> LauncherPaths {
        let paths = request.storage
        guard request.version == MonitorLaunchRequest.currentVersion,
              paths.instanceDirectories.count == 1, paths.instanceDirectories[request.instanceID] != nil,
              paths.instanceRunDirectories?[request.instanceID] != nil else { throw RuriError.message(Messages.CoreGameMonitor.invalidMonitorRequest) }
        try paths.validateDirectoryConfiguration()
        try paths.validateInstanceLocation(request.instanceID)
        return paths
    }
}
