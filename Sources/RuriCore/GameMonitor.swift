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
}
struct MonitorStopRequest: Codable {
    let version: Int
    let sessionID: UUID
}

public enum GameMonitorClient {
    public enum Activity: Equatable, Sendable { case inactive, monitoring, orphaned, uncertain }
    public enum ClientEvent: String, Codable, Sendable { case connected, windowClosed, windowReopened, quitRequested, normalQuitRequested, stopRequested, gameActivationRequested }
    public static func recordEvent(_ event: ClientEvent, paths: LauncherPaths, session: GameSession) throws {
        struct Entry: Encodable { let date: Date; let clientPID: Int32; let client: String; let event: ClientEvent }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        let url = try LauncherPaths.safePath("client-events.jsonl", within: directory)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message("无法记录启动器事件。") }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw RuriError.message("启动器事件记录不是普通文件。") }
        var data = try JSONEncoder().encode(Entry(date: Date(), clientPID: ProcessInfo.processInfo.processIdentifier, client: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName, event: event))
        data.append(10)
        guard data.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == data.count else { throw RuriError.message("无法保存启动器事件。") }
    }
    public static func activity(_ record: GameSession) -> Activity {
        if record.monitorIdentity?.isAlive == true { return .monitoring }
        if record.state.isFinished || record.monitorIdentity == nil { return .inactive }
        if record.monitorIdentity?.liveness == .unverifiable { return .uncertain }
        if record.gameIdentity?.isAlive == true { return .orphaned }
        // A monitor may have died between spawning Java and saving its identity.
        if record.gameIdentity == nil || record.gameIdentity?.liveness == .unverifiable { return .uncertain }
        return .inactive
    }
    public static func helperExecutable() throws -> URL {
        guard let executable = Bundle.main.executableURL else { throw RuriError.message("无法定位游戏监控组件。") }
        let parent = executable.deletingLastPathComponent()
        let candidates = [parent.deletingLastPathComponent().appendingPathComponent("Helpers/ruri-monitor"), parent.appendingPathComponent("ruri-monitor")]
        guard let helper = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw RuriError.message("缺少游戏监控组件，请重新构建或安装 Ruri。") }
        return helper
    }
    @MainActor public static func start(plan: LaunchPlan, recorder: GameSessionRecorder, paths: LauncherPaths, secrets: [String], helper: URL? = nil) throws {
        let process = Process(), input = Pipe()
        process.executableURL = try helper ?? helperExecutable()
        process.arguments = ["run"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = paths.instance(recorder.record.instanceID)
        try process.run()
        defer { try? input.fileHandleForWriting.close() }
        guard let identity = ProcessIdentity.read(process.processIdentifier) else { throw RuriError.message("无法确认游戏监控组件的身份。") }
        let request = MonitorLaunchRequest(version: 4, root: paths.root, instanceID: recorder.record.instanceID, sessionID: recorder.record.id,
                                           monitor: identity, plan: plan, secrets: secrets, storage: paths.monitorSnapshot(for: recorder.record.instanceID))
        let data = try JSONEncoder().encode(request)
        guard data.count <= 2_097_152 else { throw RuriError.message("游戏启动信息超过监控组件限制。") }
        try recorder.handoff(to: identity)
        // No launch arguments, access tokens or refresh tokens are written to a
        // transport file or placed on the monitor's own command line.
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    public static func requestStop(paths: LauncherPaths, record: GameSession) throws {
        guard !record.state.isFinished, record.monitorIdentity?.isAlive == true else { throw RuriError.message("游戏监控已断开或游戏已结束，无法发送结束请求。") }
        let current = try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        guard current.monitorIdentity == record.monitorIdentity, !current.state.isFinished else { throw RuriError.message("运行会话已经发生变化，请刷新后重试。") }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        try JSONEncoder().encode(MonitorStopRequest(version: 1, sessionID: record.id)).write(to: directory.appendingPathComponent("stop-request.json"), options: .atomic)
        try? recordEvent(.stopRequested, paths: paths, session: record)
    }
    public static func wait(paths: LauncherPaths, instanceID: UUID, sessionID: UUID) async throws -> GameSession {
        while true {
            let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
            switch activity(record) {
            case .monitoring: try await Task.sleep(for: .milliseconds(250))
            case .orphaned: throw RuriError.message("游戏仍在运行，但监控组件已经中断。请在游戏中正常退出。")
            case .uncertain: throw RuriError.message("监控组件在启动时中断，无法确认游戏状态，请检查运行记录。")
            case .inactive: return record
            }
        }
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
                guard data.count <= 2_097_152 else { throw RuriError.message("启动信息超过大小限制。") }
            }
            let decoded = try JSONDecoder().decode(MonitorLaunchRequest.self, from: data)
            request = decoded
            guard (1...4).contains(decoded.version), decoded.root.isFileURL, decoded.plan.executable.isFileURL,
                  decoded.monitor == ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier) else { throw RuriError.message("游戏监控请求无效。") }
            let paths = try validatedPaths(decoded)
            guard decoded.plan.directory.resolvingSymlinksInPath() == paths.game(decoded.instanceID).resolvingSymlinksInPath() else { throw RuriError.message("游戏目录与运行会话不一致。") }
            let recorder = try GameSessionRecorder(resuming: decoded.sessionID, instanceID: decoded.instanceID, paths: paths, monitor: decoded.monitor)
            recorder.addSecrets(decoded.secrets)
            return try await run(decoded.plan, recorder: recorder, paths: paths, secrets: decoded.secrets)
        } catch {
            if let request { try? recordUnstartedFailure(request, error: error) }
            return 1
        }
    }
    @MainActor private static func run(_ plan: LaunchPlan, recorder: GameSessionRecorder, paths: LauncherPaths, secrets: [String]) async throws -> Int32 {
        let game = GameProcess()
        try recorder.setNativeQuitSupported(plan.nativeQuitSupported == true)
        var stopTask: Task<Void, Never>?
        defer { stopTask?.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try game.start(plan: plan, secrets: secrets) { line in
                    try? recorder.append(line)
                } onExit: { result in
                    do { try recorder.finish(exit: result) }
                    catch { try? recorder.close() }
                    try? result.save(paths: paths, instanceID: recorder.record.instanceID)
                    continuation.resume(returning: result.shellStatus)
                }
                if let pid = game.processIdentifier {
                    do { try recorder.started(processID: pid) }
                    catch { try? recorder.append("[Ruri] 无法保存游戏进程信息：\(error.localizedDescription)") }
                }
                stopTask = Task { @MainActor in
                    var lastNormalQuit = recorder.record.normalQuitAttempt?.requestID
                    while !Task.isCancelled && game.isRunning {
                        if stopRequested(recorder) {
                            try? recorder.transition(.stopping)
                            game.stop()
                            return
                        }
                        if let request = GameMonitorClient.normalQuitRequest(directory: recorder.directory, session: recorder.record), request.id != lastNormalQuit {
                            lastNormalQuit = request.id
                            let accepted = game.requestNormalQuit()
                            try? recorder.recordNormalQuit(request, accepted: accepted)
                        }
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
            } catch { continuation.resume(throwing: error) }
        }
    }
    @MainActor private static func stopRequested(_ recorder: GameSessionRecorder) -> Bool {
        guard let url = try? LauncherPaths.safePath("stop-request.json", within: recorder.directory),
              let attributes = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), attributes.isRegularFile == true,
              (attributes.fileSize ?? .max) <= 1024,
              let data = try? Data(contentsOf: url), let request = try? JSONDecoder().decode(MonitorStopRequest.self, from: data) else { return false }
        return request.version == 1 && request.sessionID == recorder.record.id
    }
    @MainActor private static func recordUnstartedFailure(_ request: MonitorLaunchRequest, error: any Error) throws {
        guard request.monitor.pid == ProcessInfo.processInfo.processIdentifier, request.monitor.isAlive else { return }
        let paths = try validatedPaths(request)
        var record = try GameSessionStore.load(paths: paths, instanceID: request.instanceID, sessionID: request.sessionID)
        guard !record.state.isFinished, record.processID == nil, record.monitorIdentity == request.monitor else { return }
        var redactor = GameLogRedactor(); redactor.addSecrets(request.secrets)
        record.state = .failed; record.failure = redactor.redact(String(error.localizedDescription.prefix(32768))); record.updatedAt = Date()
        let directory = try GameSessionStore.directory(paths: paths, instanceID: request.instanceID, sessionID: request.sessionID)
        try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
        let handle = try FileHandle(forWritingTo: GameSessionStore.logURL(paths: paths, session: record)); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(("[Ruri] \(record.failure ?? "监控启动失败")\n").utf8))
    }
    static func validatedPaths(_ request: MonitorLaunchRequest) throws -> LauncherPaths {
        if request.version == 1 { return LauncherPaths(root: request.root) }
        guard (2...4).contains(request.version), let paths = request.storage, paths.root == request.root,
              paths.instanceDirectories.count == 1, paths.instanceDirectories[request.instanceID] != nil else { throw RuriError.message("游戏监控缺少实例文件夹信息。") }
        guard request.version >= 3 || paths.runDirectory(for: request.instanceID) == .isolated else { throw RuriError.message("共享运行目录需要新版监控协议。") }
        if request.version >= 3, paths.instanceRunDirectories?[request.instanceID] == nil { throw RuriError.message("游戏监控缺少运行目录策略。") }
        try paths.validateDirectoryConfiguration()
        try paths.validateInstanceLocation(request.instanceID)
        return paths
    }
}
