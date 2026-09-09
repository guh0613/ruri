import Foundation

public struct GameExit: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable { case exit, signal }
    public let status: Int32
    public let reason: Reason
    public let processID: Int32
    public let startedAt: Date
    public let endedAt: Date
    public let stopRequested: Bool
    public var durationSeconds: Double?
    public var normalQuitRequested: Bool?
    public var playTime: TimeInterval { max(0, durationSeconds ?? endedAt.timeIntervalSince(startedAt)) }

    public var succeeded: Bool { reason == .exit && status == 0 }
    public var stoppedByLauncher: Bool {
        stopRequested && (succeeded || (reason == .signal && status == 15) || (reason == .exit && status == 143))
    }
    public var requiresAttention: Bool { !succeeded && !stoppedByLauncher }
    public var shellStatus: Int32 { reason == .signal ? 128 + status : status }
    public var summary: String {
        if stoppedByLauncher { return "游戏已按要求结束" }
        if succeeded { return "游戏已正常退出" }
        if reason == .signal { return "游戏进程因 \(signalName) 退出" }
        return "游戏异常退出（退出码 \(status)）"
    }
    public var explanation: String {
        if stoppedByLauncher { return "Ruri 发送了结束请求，本次退出不作为游戏崩溃处理。" }
        if succeeded { return normalQuitRequested == true ? "Ruri 曾发送正常退出请求，游戏进程随后返回成功状态。" : "游戏进程返回成功状态。" }
        if reason == .signal && [9, 15].contains(status) {
            return "进程收到了终止信号；当前记录无法确定发送者，单凭信号不能判断是游戏崩溃。"
        }
        if reason == .exit && status == 143 {
            return "Java 收到结束信号后可能返回 143；当前没有 Ruri 主动结束的记录，需要结合日志判断。"
        }
        return "退出状态不能单独说明原因，请查看本次运行日志和生成的崩溃报告。"
    }
    public var logDescription: String {
        "[Ruri] \(summary)；PID \(processID)；\(reason == .signal ? "信号" : "退出码") \(status)；Ruri 结束请求：\(stopRequested ? "是" : "否")；正常退出请求：\(normalQuitRequested == true ? "是" : "否")；开始 \(startedAt.ISO8601Format())；结束 \(endedAt.ISO8601Format())"
    }
    private var signalName: String {
        [2: "SIGINT", 6: "SIGABRT", 9: "SIGKILL", 11: "SIGSEGV", 15: "SIGTERM"][status] ?? "信号 \(status)"
    }
    public func save(paths: LauncherPaths, instanceID: UUID) throws {
        let url = try LauncherPaths.safePath("last-exit.json", within: paths.instance(instanceID))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public struct GameCrashReport: Identifiable, Sendable {
    public enum Kind: String, Sendable { case minecraft = "Minecraft", jvm = "Java 虚拟机" }
    public let url: URL
    public let kind: Kind
    public var id: String { url.path }

    /// Only associate files from this launch; previous reports must not diagnose a later exit.
    public static func find(in game: URL, exit: GameExit) -> [GameCrashReport] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        var candidates: [(URL, Kind)] = []
        if (try? game.appendingPathComponent("crash-reports").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
           let directory = try? LauncherPaths.safePath("crash-reports", within: game),
           let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) {
            candidates += files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "txt" }.map { ($0, .minecraft) }
        }
        let jvmName = "hs_err_pid\(exit.processID).log"
        if (try? game.appendingPathComponent(jvmName).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
           let jvm = try? LauncherPaths.safePath(jvmName, within: game) { candidates.append((jvm, .jvm)) }
        return candidates.compactMap { url, kind -> GameCrashReport? in
            guard let attributes = try? url.resourceValues(forKeys: keys), attributes.isRegularFile == true,
                  attributes.isSymbolicLink == false, let modified = attributes.contentModificationDate,
                  modified >= exit.startedAt, modified <= exit.endedAt.addingTimeInterval(5) else { return nil }
            return GameCrashReport(url: url, kind: kind)
        }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
}
