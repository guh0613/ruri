import Foundation
import RuriLocalization

public struct GameExit: Codable, Equatable, Sendable {
    package init(
        status: Int32, reason: Reason, processID: Int32, startedAt: Date, endedAt: Date, stopRequested: Bool,
        durationSeconds: Double? = nil, normalQuitRequested: Bool? = nil, reportedFailure: Bool? = nil,
        awakeDurationSeconds: Double? = nil
    ) {
        self.status = status
        self.reason = reason
        self.processID = processID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stopRequested = stopRequested
        self.durationSeconds = durationSeconds
        self.normalQuitRequested = normalQuitRequested
        self.reportedFailure = reportedFailure
        self.awakeDurationSeconds = awakeDurationSeconds
    }

    public enum Reason: String, Codable, Sendable { case exit, signal }
    public let status: Int32
    public let reason: Reason
    public let processID: Int32
    public let startedAt: Date
    public let endedAt: Date
    public let stopRequested: Bool
    public var durationSeconds: Double?
    public var normalQuitRequested: Bool?
    public var reportedFailure: Bool? = nil
    public var awakeDurationSeconds: Double? = nil
    public var playTime: TimeInterval { max(0, awakeDurationSeconds ?? durationSeconds ?? endedAt.timeIntervalSince(startedAt)) }

    public var succeeded: Bool { reason == .exit && status == 0 && reportedFailure != true }
    public var stoppedByLauncher: Bool {
        stopRequested && (succeeded || (reason == .signal && status == 15) || (reason == .exit && status == 143))
    }
    public var requiresAttention: Bool { !succeeded && !stoppedByLauncher }
    public var shellStatus: Int32 { reportedFailure == true && status == 0 ? 1 : reason == .signal ? 128 + status : status }
    public var summary: String { summaryMessage.localized }
    public var summaryMessage: LocalizedMessage {
        if stoppedByLauncher { return Messages.CoreGameExit.requestedExit }
        if reportedFailure == true { return Messages.MonitorLogging.reportedFailure }
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

}
