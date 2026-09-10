import Foundation
import Darwin

public struct GameSessionInterruption: Codable, Equatable, Sendable {
    public enum Resolution: String, Codable, Sendable { case knownProcessEnded, userConfirmedEnded }
    public let resolution: Resolution
    public let observedAt: Date
    public let previousStage: GameSession.Stage
    public let explanation: String
}

public enum GameSessionRecovery {
    public enum Status: Equatable, Sendable {
        case finished, monitoring, monitorUnconfirmed, gameRunning, commandRunning, processEnded, confirmationRequired
        public var title: String {
            switch self {
            case .finished: "运行记录已经结束"
            case .monitoring: "监控组件仍在运行"
            case .monitorUnconfirmed: "暂时无法核对监控进程"
            case .gameRunning: "游戏仍在运行，监控已断开"
            case .commandRunning: "启动命令仍在运行，监控已断开"
            case .processEnded: "游戏进程已消失，缺少退出结果"
            case .confirmationRequired: "监控已中断，无法确认游戏状态"
            }
        }
        public var explanation: String {
            switch self {
            case .finished: "无需再恢复这条记录。"
            case .monitoring: "请等待监控完成收尾，或返回游戏查看当前状态。"
            case .monitorUnconfirmed: "系统没有提供足够的进程信息，当前不能确认监控是否已经退出。请稍后刷新；这时不会收尾仍可能被写入的记录。"
            case .gameRunning: "进程身份仍然匹配。请先返回游戏，通过游戏菜单退出；这期间控制台输出可能无法继续保存。"
            case .commandRunning: "命令进程仍然存在。请先在活动监视器中结束该命令，再恢复记录；不会重新执行这条命令。"
            case .processEnded: "已核对记录中的进程身份，原进程不再存在。可以收尾中断记录，恢复这个实例的启动入口；退出码和结束时间将保留为未知。"
            case .confirmationRequired: "监控没能保存可核对的游戏进程身份。请先在游戏、Dock 或活动监视器中确认该实例已退出，再恢复启动入口。Ruri 无法代替你确认这一点。"
            }
        }
    }
    public static func status(_ record: GameSession) -> Status {
        if record.state.isFinished { return .finished }
        if record.monitorIdentity?.isAlive == true { return .monitoring }
        if record.monitorIdentity?.liveness == .unverifiable { return .monitorUnconfirmed }
        if record.commandIdentity?.isAlive == true { return .commandRunning }
        if record.commandIdentity?.liveness == .unverifiable { return .confirmationRequired }
        if record.gameIdentity?.isAlive == true { return .gameRunning }
        if record.stage == .afterCommand && record.commandIdentity == nil && record.commandResults?.last?.phase != .after { return .confirmationRequired }
        if record.stage == .beforeCommand && record.commandIdentity != nil { return .processEnded }
        return record.gameIdentity == nil || record.gameIdentity?.liveness == .unverifiable ? .confirmationRequired : .processEnded
    }

    /// Finalize only the interrupted record. Never fabricate a Process exit,
    /// send a signal, remove a lock file, or credit an unknown play duration.
    public static func finish(paths: LauncherPaths, expected: GameSession, userConfirmedEnded: Bool = false) throws -> GameSession {
        let lease = try GameRunLease.acquire(paths: paths, instanceID: expected.instanceID, ignoringSession: expected.id)
        defer { withExtendedLifetime(lease) {} }
        var record = try GameSessionStore.load(paths: paths, instanceID: expected.instanceID, sessionID: expected.id)
        guard record == expected else { throw RuriError.message("运行记录已经变化，请刷新状态后重试。") }
        let resolution: GameSessionInterruption.Resolution
        switch status(record) {
        case .finished: throw RuriError.message("这次运行已经完成，不需要恢复。")
        case .monitoring: throw RuriError.message("监控仍在运行，不能收尾它正在写入的记录。")
        case .monitorUnconfirmed: throw RuriError.message("无法确认监控已退出，请稍后刷新状态。")
        case .gameRunning: throw RuriError.message("游戏进程仍然存在，请先在游戏中退出。")
        case .commandRunning: throw RuriError.message("启动命令仍然存在，请先结束该命令。")
        case .processEnded: resolution = .knownProcessEnded
        case .confirmationRequired:
            guard userConfirmedEnded else { throw RuriError.message("尚未确认游戏已退出，无法恢复实例启动。") }
            resolution = .userConfirmedEnded
        }
        let date = Date()
        if let exit = record.exit {
            let explanation = "监控在退出收尾期间中断，已保留取得的游戏退出码与游玩时长；不会重新执行退出后命令。"
            if record.stage == .afterCommand && record.commandResults?.last?.phase != .after {
                record.commandResults = (record.commandResults ?? []) + [GameCommandResult(phase: .after, startedAt: record.updatedAt, endedAt: date, status: nil, cancelled: false, timedOut: false, error: "监控中断，命令结果未知")]
            }
            record.commandIdentity = nil
            record.state = exit.stoppedByLauncher ? .stopped : exit.succeeded ? .succeeded : .failed
            record.stage = .finished; record.updatedAt = date
            if record.events.count < 512 { record.events.append(.init(id: UUID(), date: date, stage: .monitorRecovery, message: explanation)) }
            let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
            try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
            try GamePlaytimeStore.record(record, paths: paths)
            try? lease.clearReservation(session: record)
            try? appendRecoveryLog(explanation, date: date, paths: paths, record: record)
            return record
        }
        let explanation = resolution == .knownProcessEnded
            ? "监控已中断，核对记录中的身份后确认原游戏进程已消失。没有取得实际退出码或退出时间。"
            : "监控已中断且缺少游戏进程身份，由用户确认游戏已退出后收尾。没有取得实际退出码或退出时间。"
        record.interruption = .init(resolution: resolution, observedAt: date, previousStage: record.stage, explanation: explanation)
        record.state = .interrupted; record.stage = .monitorRecovery; record.updatedAt = date
        record.exit = nil
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: date, stage: .monitorRecovery, message: explanation)) }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        let url = try LauncherPaths.safePath("session.json", within: directory)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: url, options: .atomic)
        try? lease.clearReservation(session: record)
        // Metadata is authoritative even if a damaged/unwritable output log
        // cannot accept this additional event.
        try? appendRecoveryLog(explanation, date: date, paths: paths, record: record)
        return record
    }
    private static func appendRecoveryLog(_ text: String, date: Date, paths: LauncherPaths, record: GameSession) throws {
        let url = try GameSessionStore.logURL(paths: paths, session: record)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message("无法追加恢复日志。") }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw RuriError.message("运行日志不是普通文件。") }
        let data = Data(("\n[Ruri] \(date.ISO8601Format()) \(text)\n").utf8)
        guard data.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == data.count else { throw RuriError.message("无法保存恢复日志。") }
    }
}
