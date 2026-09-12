import RuriLocalization
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
    public var summary: String { summaryMessage.localized }
    public var summaryMessage: LocalizedMessage {
        if stoppedByLauncher { return Messages.CoreGameExit.requestedExit }
        if succeeded { return Messages.CoreGameExit.normalExit }
        if reason == .signal { return Messages.CoreGameExit.processExitReason(String(describing: signalName)) }
        return Messages.CoreGameExit.crashExit(String(describing: status))
    }
    public var explanation: String {
        if stoppedByLauncher { return Messages.CoreGameExit.ruriRequestedExit.localized }
        if succeeded { return normalQuitRequested == true ? Messages.CoreGameExit.normalExitSucceeded.localized : Messages.CoreGameExit.processExitedSuccessfully.localized }
        if reason == .signal && [9, 15].contains(status) {
            return Messages.CoreGameExit.terminationSignalReceived.localized
        }
        if reason == .exit && status == 143 {
            return Messages.CoreGameExit.javaTerminationSignal.localized
        }
        return Messages.CoreGameExit.exitStatusNeedsLogs.localized
    }
    public var logDescription: String {
        Messages.CoreGameExit.exitLogLine(summary, String(describing: processID), String(describing: reason == .signal ? Messages.CoreGameExit.signalLabel.localized : Messages.CoreGameExit.exitCodeLabel.localized), String(describing: status), String(describing: stopRequested ? Messages.CoreGameExit.yesLabel.localized : Messages.CoreGameExit.noLabel.localized), String(describing: normalQuitRequested == true ? Messages.CoreGameExit.yesLabel.localized : Messages.CoreGameExit.noLabel.localized), String(describing: startedAt.ISO8601Format()), String(describing: endedAt.ISO8601Format())).localized
    }
    private var signalName: String {
        [2: "SIGINT", 6: "SIGABRT", 9: "SIGKILL", 11: "SIGSEGV", 15: "SIGTERM"][status] ?? Messages.CoreGameExit.signalValue(String(describing: status)).localized
    }
    public func save(paths: LauncherPaths, instanceID: UUID) throws {
        let url = try LauncherPaths.safePath("last-exit.json", within: paths.instance(instanceID))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public struct GameCrashReport: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case minecraft = "Minecraft", jvm
        public var title: String { switch self { case .minecraft: "Minecraft"; case .jvm: Messages.CoreGameExit.javaVirtualMachine.localized } }
    }
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
