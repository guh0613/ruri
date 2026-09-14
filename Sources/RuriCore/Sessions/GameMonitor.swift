import RuriLocalization
import Foundation
import Darwin

struct MonitorLaunchRequest: Codable {
    let version: Int
    let root: URL
    let instanceID: UUID
    let sessionID: UUID
    let monitor: ProcessIdentity
    let plan: LaunchPlan
    let secrets: [String]
    var storage: LauncherPaths? = nil
    var language: String? = nil
    var region: String? = nil
}
struct MonitorStopRequest: Codable {
    let version: Int
    let sessionID: UUID
}
struct MonitorLogRequest: Codable {
    let version: Int
    let sessionID: UUID
    let id: UUID
}

public enum GameMonitorClient {
    public enum Activity: Equatable, Sendable { case inactive, monitoring, orphaned, uncertain }
    public enum ClientEvent: String, Codable, Sendable { case connected, windowClosed, windowReopened, quitRequested, normalQuitRequested, stopRequested, gameActivationRequested }
    public static func recordEvent(_ event: ClientEvent, paths: LauncherPaths, session: GameSession) throws {
        guard session.debugLogging == true else { return }
        struct Entry: Encodable { let date: Date; let clientPID: Int32; let client: String; let event: ClientEvent }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        let url = try LauncherPaths.safePath("client-events.jsonl", within: directory)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreGameMonitor.launcherEventRecordFailed) }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw RuriError.message(Messages.CoreGameMonitor.launcherEventNotRegularFile) }
        var data = try JSONEncoder().encode(Entry(date: Date(), clientPID: ProcessInfo.processInfo.processIdentifier, client: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, event: event))
        data.append(10)
        guard data.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == data.count else { throw RuriError.message(Messages.CoreGameMonitor.launcherEventSaveFailed) }
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
    public static func helperExecutable() throws -> URL {
        guard let executable = Bundle.main.executableURL else { throw RuriError.message(Messages.CoreGameMonitor.monitorComponentMissing) }
        let parent = executable.deletingLastPathComponent()
        let candidates = [parent.deletingLastPathComponent().appendingPathComponent("Helpers/ruri-monitor"), parent.appendingPathComponent("ruri-monitor")]
        guard let helper = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw RuriError.message(Messages.CoreGameMonitor.monitorComponentNotFound) }
        return helper
    }
    @MainActor public static func start(plan: LaunchPlan, recorder: GameSessionRecorder, paths: LauncherPaths, secrets: [String], helper: URL? = nil) throws {
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
        let request = MonitorLaunchRequest(version: 8, root: paths.root, instanceID: recorder.record.instanceID, sessionID: recorder.record.id,
                                           monitor: identity, plan: plan, secrets: secrets, storage: paths.monitorSnapshot(for: recorder.record.instanceID),
                                           language: LocalizationContext.current.language, region: LocalizationContext.current.regionIdentifier)
        let data = try JSONEncoder().encode(request)
        guard data.count <= 2_097_152 else { throw RuriError.message(Messages.CoreGameMonitor.launchInfoTooLarge) }
        try recorder.handoff(to: identity)
        // No launch arguments, access tokens or refresh tokens are written to a
        // transport file or placed on the monitor's own command line.
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    public static func requestStop(paths: LauncherPaths, record: GameSession) throws {
        guard !record.state.isFinished, record.monitorIdentity?.isAlive == true else { throw RuriError.message(Messages.CoreGameMonitor.monitorDisconnected) }
        let current = try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        guard current.monitorIdentity == record.monitorIdentity, !current.state.isFinished else { throw RuriError.message(Messages.CoreGameMonitor.sessionChanged) }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        try JSONEncoder().encode(MonitorStopRequest(version: 1, sessionID: record.id)).write(to: directory.appendingPathComponent("stop-request.json"), options: .atomic)
        try? recordEvent(.stopRequested, paths: paths, session: record)
    }
    public static func wait(paths: LauncherPaths, instanceID: UUID, sessionID: UUID) async throws -> GameSession {
        while true {
            let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
            switch activity(record) {
            case .monitoring: try await Task.sleep(for: .milliseconds(250))
            case .orphaned: throw RuriError.message(Messages.CoreGameMonitor.gameStillRunning)
            case .uncertain: throw RuriError.message(Messages.CoreGameMonitor.monitorInterruptedAtLaunch)
            case .inactive: return record
            }
        }
    }
    /// Only a visible log window requests snapshots. Credentials never leave
    /// the monitor; it formats and redacts its bounded tail before writing it.
    public static func requestLogSnapshot(paths: LauncherPaths, session: GameSession) throws {
        guard !session.state.isFinished, session.debugLogging != true, session.monitorIdentity?.isAlive == true else { return }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        let file = try LauncherPaths.safePath("log-request.json", within: directory)
        try JSONEncoder().encode(MonitorLogRequest(version: 1, sessionID: session.id, id: UUID())).write(to: file, options: .atomic)
    }
    public static func logPreview(paths: LauncherPaths, session: GameSession) throws -> String {
        if let preview = try previewURL(paths: paths, session: session) { return String(decoding: try Data(contentsOf: preview), as: UTF8.self) }
        return try GameSessionStore.logTail(paths: paths, session: session)
    }
    static func previewURL(paths: LauncherPaths, session: GameSession) throws -> URL? {
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        let preview = try LauncherPaths.safePath("log-preview.log", within: directory)
        if !session.state.isFinished, session.debugLogging != true,
           let values = try? preview.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
           values.isRegularFile == true, (values.fileSize ?? .max) <= 2_097_152 {
            return preview
        }
        return nil
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
            guard (1...8).contains(decoded.version), decoded.root.isFileURL, decoded.plan.executable.isFileURL,
                  (decoded.plan.offlineSkin == nil || decoded.version >= 7),
                  decoded.monitor == ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier) else { throw RuriError.message(Messages.CoreGameMonitor.invalidMonitorRequest) }
            let context = LocalizationContext(language: decoded.language, region: decoded.region ?? Locale.current.identifier)
            return try await LocalizationContext.$current.withValue(context) {
                let paths = try validatedPaths(decoded)
                guard decoded.plan.directory.resolvingSymlinksInPath() == paths.game(decoded.instanceID).resolvingSymlinksInPath() else { throw RuriError.message(Messages.CoreGameMonitor.sessionDirectoryMismatch) }
                let recorder = try GameSessionRecorder(resuming: decoded.sessionID, instanceID: decoded.instanceID, paths: paths, monitor: decoded.monitor)
                recorder.addSecrets(decoded.secrets + decoded.plan.environmentRedactions)
                try recorder.configureLogging(debug: decoded.plan.debugLogging == true)
                return try await run(decoded.plan, recorder: recorder, paths: paths, secrets: decoded.secrets)
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
    @MainActor private static func run(_ inputPlan: LaunchPlan, recorder: GameSessionRecorder, paths: LauncherPaths, secrets: [String]) async throws -> Int32 {
        var plan = inputPlan
        try plan.commands?.validate()
        let javaLease = try JavaRuntimeLease.shared(binary: plan.executable, paths: paths)
        defer { withExtendedLifetime(javaLease) {} }
        if stopRequested(recorder) { try recorder.fail(CancellationError(), cancelled: true); return 130 }
        if let commands = plan.commands, commands.enabled, !commands.before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let result = await GameCommandRunner.run(commands.before, phase: .before, plan: plan, timeoutSeconds: commands.timeoutSeconds, recorder: recorder) { stopRequested(recorder) }
            if !result.succeeded {
                try recorder.fail(RuriError.message(result.summaryMessage), cancelled: result.cancelled)
                return result.cancelled ? 130 : 1
            }
        }
        if stopRequested(recorder) { try recorder.fail(CancellationError(), cancelled: true); return 130 }
        var skinServer: OfflineSkinServer?
        defer { skinServer?.stop() }
        if let skin = plan.offlineSkin {
            let server = try await OfflineSkinServer.start(skin)
            skinServer = server
            plan = try server.applying(to: plan)
            try recorder.append(Messages.OfflineSkin.ready.localized)
            try recorder.append("[Ruri] \(plan.redactedCommand)")
        }
        if stopRequested(recorder) { try recorder.fail(CancellationError(), cancelled: true); return 130 }
        if recorder.record.stage != .starting { try recorder.transition(.starting) }
        let game = GameProcess()
        let capture = try recorder.makeOutputCapture()
        recorder.retainOutput(capture)
        let controls = FileChangeObserver(directories: [recorder.directory], fallbackSeconds: 5)
        defer { controls.cancel() }
        try recorder.setNativeQuitSupported(plan.nativeQuitSupported == true)
        var stopTask: Task<Void, Never>?
        defer { stopTask?.cancel() }
        var result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GameExit, any Error>) in
            do {
                try game.start(plan: plan, capture: capture) { result in
                    continuation.resume(returning: result)
                }
                if let pid = game.processIdentifier {
                    do { try recorder.started(processID: pid) }
                    catch { try? recorder.append(Messages.CoreGameMonitor.gameProcessInfoSaveFailed(error.localizedDescription).localized) }
                }
                stopTask = Task { @MainActor in
                    var lastNormalQuit = recorder.record.normalQuitAttempt?.requestID
                    var lastLogRequest: UUID?
                    @MainActor func processRequests() -> Bool {
                        if stopRequested(recorder) {
                            try? recorder.transition(.stopping)
                            game.stop()
                            return false
                        }
                        if let request = GameMonitorClient.normalQuitRequest(directory: recorder.directory, session: recorder.record), request.id != lastNormalQuit {
                            lastNormalQuit = request.id
                            let accepted = game.requestNormalQuit()
                            try? recorder.recordNormalQuit(request, accepted: accepted)
                        }
                        if let request = logRequest(recorder), request.id != lastLogRequest {
                            lastLogRequest = request.id
                            if let file = try? LauncherPaths.safePath("log-preview.log", within: recorder.directory) {
                                try? Data(capture.snapshot().utf8).write(to: file, options: .atomic)
                            }
                        }
                        return true
                    }
                    guard processRequests() else { return }
                    for await _ in controls.events {
                        guard !Task.isCancelled, game.isRunning, processRequests() else { return }
                    }
                }
            } catch { continuation.resume(throwing: error) }
        }
        stopTask?.cancel()
        if result.succeeded && !result.stopRequested {
            // Some legacy loaders swallow a crash and exit with code zero.
            let markers = ["Crash report saved to", "Could not save crash report to", "This crash report has been saved to:", "Unable to launch", "An exception was thrown, the game will display an error screen and halt."]
            let tail = capture.snapshot(final: true)
            if markers.contains(where: tail.contains) || !GameCrashReport.find(in: plan.directory, exit: result).isEmpty { result.reportedFailure = true }
        }
        try recorder.recordGameExit(result)
        if !result.stopRequested, let commands = plan.commands, commands.enabled, !commands.after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = await GameCommandRunner.run(commands.after, phase: .after, plan: plan, timeoutSeconds: commands.timeoutSeconds, exit: result, recorder: recorder) { stopRequested(recorder) }
        }
        try recorder.finish(exit: result)
        return result.shellStatus
    }
    @MainActor private static func stopRequested(_ recorder: GameSessionRecorder) -> Bool {
        guard let url = try? LauncherPaths.safePath("stop-request.json", within: recorder.directory),
              let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), attributes.isRegularFile == true,
              (attributes.fileSize ?? .max) <= 1024,
              let data = try? Data(contentsOf: url), let request = try? JSONDecoder().decode(MonitorStopRequest.self, from: data) else { return false }
        return request.version == 1 && request.sessionID == recorder.record.id
    }
    @MainActor private static func logRequest(_ recorder: GameSessionRecorder) -> MonitorLogRequest? {
        guard let file = try? LauncherPaths.safePath("log-request.json", within: recorder.directory),
              let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              attributes.isRegularFile == true, (attributes.fileSize ?? .max) <= 1024,
              let data = try? Data(contentsOf: file), let request = try? JSONDecoder().decode(MonitorLogRequest.self, from: data),
              request.version == 1, request.sessionID == recorder.record.id else { return nil }
        return request
    }
    @MainActor private static func recordUnstartedFailure(_ request: MonitorLaunchRequest, error: any Error) throws {
        guard request.monitor.pid == ProcessInfo.processInfo.processIdentifier, request.monitor.isAlive else { return }
        let paths = try validatedPaths(request)
        var record = try GameSessionStore.load(paths: paths, instanceID: request.instanceID, sessionID: request.sessionID)
        guard !record.state.isFinished, record.processID == nil, record.monitorIdentity == request.monitor else { return }
        var redactor = GameLogRedactor(); redactor.addSecrets(request.secrets)
        record.state = .failed; record.failure = redactor.redact(String(error.localizedDescription.prefix(32768))); record.updatedAt = Date()
        record.failureMessage = (error as? RuriError)?.localizedMessage?.recorded(limit: 32768, redact: redactor.redact)
        let directory = try GameSessionStore.directory(paths: paths, instanceID: request.instanceID, sessionID: request.sessionID)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
        let handle = try FileHandle(forWritingTo: GameSessionStore.logURL(paths: paths, session: record)); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(("[Ruri] \(record.failure ?? Messages.CoreGameMonitor.monitorStartFailed.localized)\n").utf8))
    }
    static func validatedPaths(_ request: MonitorLaunchRequest) throws -> LauncherPaths {
        if request.version == 1 { return LauncherPaths(root: request.root) }
        guard (2...8).contains(request.version), let paths = request.storage, paths.root == request.root,
              paths.instanceDirectories.count == 1, paths.instanceDirectories[request.instanceID] != nil else { throw RuriError.message(Messages.CoreGameMonitor.instanceFolderMissing) }
        guard request.version >= 3 || paths.runDirectory(for: request.instanceID) == .isolated else { throw RuriError.message(Messages.CoreGameMonitor.sharedDirectoryProtocolRequired) }
        if request.version >= 3, paths.instanceRunDirectories?[request.instanceID] == nil { throw RuriError.message(Messages.CoreGameMonitor.runDirectoryPolicyMissing) }
        if paths.runDirectory(for: request.instanceID) == .custom, request.version < 5 { throw RuriError.message(Messages.CoreGameMonitor.customDirectoryProtocolRequired) }
        try paths.validateDirectoryConfiguration()
        try paths.validateInstanceLocation(request.instanceID)
        return paths
    }
}
