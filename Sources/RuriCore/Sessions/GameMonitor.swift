import RuriLocalization
import Foundation
import Darwin

public enum GameMonitorClient {
    public typealias Activity = GameMonitorActivity
    public enum ClientEvent: String, Codable, Sendable { case connected, windowClosed, windowReopened, quitRequested, normalQuitRequested, stopRequested, gameActivationRequested }
    public static func recordEvent(_ event: ClientEvent, paths: LauncherPaths, session: GameSession) throws {
        try GameSessionEventStore.append(event.rawValue, source: "client", sessionID: session.id, paths: paths)
    }
    public static func activity(_ record: GameSession) -> Activity { record.monitorActivity }
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
        if let tuning = plan.tuning { try recorder.setTuning(tuning) }
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
                                           monitor: identity, plan: plan, secrets: secrets, storage: SessionLocationSnapshot(paths: paths, instanceID: recorder.record.instanceID),
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
