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
    public var gameDirectory: URL? = nil
    public var nativeLogs: [GameLogReference]? = nil
    public var logBaseline: [GameLogReference]? = nil
    public let id: UUID
    public let instanceID: UUID
    public let instanceName: String
    public let gameVersion: String
    public let loader: String
    public let loaderVersion: String?
    public var memoryMB: Int
    public var memory: LaunchMemory?
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
    public var debugLogging = false
    public var host: GameHostStatus? = nil
    public var revision: UInt64 = 0
    public var finalSnapshot = false
    public var timing: GameSessionTiming? = nil
    public var controlEndpoint: String? = nil
    public var launcherVersion: String? = nil
    public var artifactState: ArtifactState? = nil
    public var outputTruncated: Bool? = nil
    public enum ArtifactState: String, Codable, Sendable { case available, expired, unavailable }
    public func isAtLeastAsRecent(as other: GameSession) -> Bool {
        let left = revision, right = other.revision
        return left == right ? updatedAt >= other.updatedAt : left > right
    }
    func validate() throws {
        guard schema == 1,
              events.count <= 512, evidence.count <= 100, instanceName.count <= 1024,
              (failure?.count ?? 0) <= 32768, timing?.isValid != false,
              (controlEndpoint?.utf8.count ?? 0) < 104, revision < UInt64(Int64.max),
              createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite,
              (nativeLogs?.count ?? 0) <= 128, (logBaseline?.count ?? 0) <= 128,
              gameDirectory == nil || gameDirectory?.isFileURL == true else {
            throw RuriError.message(Messages.CoreGameSession.invalidRunRecordFormat)
        }
        for item in evidence {
            guard item.relativePath.hasPrefix("reports/"), Self.safeRelativePath(item.relativePath), item.name.count <= 1024 else {
                throw RuriError.message(Messages.CoreGameSession.invalidRunReportPath)
            }
        }
        for item in (nativeLogs ?? []) + (logBaseline ?? []) { try item.validate() }
        if let interruption {
            guard interruption.explanation.count <= 8192, state == .interrupted, exit == nil else {
                throw RuriError.message(Messages.CoreGameSession.invalidRecoveryRecord)
            }
        }
    }
    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.utf8.contains(92) && !path.utf8.contains(0) &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == ".." || $0 == "." })
    }
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
