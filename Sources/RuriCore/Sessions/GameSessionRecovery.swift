import RuriLocalization
import Foundation
import Darwin

public struct GameSessionInterruption: Codable, Equatable, Sendable {
    public enum Resolution: String, Codable, Sendable { case knownProcessEnded, userConfirmedEnded }
    public let resolution: Resolution
    public let observedAt: Date
    public let previousStage: GameSession.Stage
    public let explanation: String
    public var explanationMessage: LocalizedMessage? = nil
    public var displayExplanation: String { explanationMessage?.localized ?? explanation }
}

public enum GameSessionRecovery {
    public enum Status: Equatable, Sendable {
        case finished, monitoring, monitorUnconfirmed, gameRunning, commandRunning, processEnded, confirmationRequired
        public var title: String {
            switch self {
            case .finished: Messages.CoreGameSessionRecovery.recordAlreadyFinished.localized
            case .monitoring: Messages.CoreGameSessionRecovery.monitorStillRunning.localized
            case .monitorUnconfirmed: Messages.CoreGameSessionRecovery.cannotCheckMonitorProcess.localized
            case .gameRunning: Messages.CoreGameSessionRecovery.gameRunningMonitorDisconnected.localized
            case .commandRunning: Messages.CoreGameSessionRecovery.launchCommandRunningMonitorDisconnected.localized
            case .processEnded: Messages.CoreGameSessionRecovery.gameProcessGoneWithoutExit.localized
            case .confirmationRequired: Messages.CoreGameSessionRecovery.monitorInterruptedUnknownGameState.localized
            }
        }
        public var explanation: String {
            switch self {
            case .finished: Messages.CoreGameSessionRecovery.noRecoveryNeeded.localized
            case .monitoring: Messages.CoreGameSessionRecovery.waitForMonitorOrCheckGame.localized
            case .monitorUnconfirmed: Messages.CoreGameSessionRecovery.insufficientProcessInformation.localized
            case .gameRunning: Messages.CoreGameSessionRecovery.matchingProcessIdentity.localized
            case .commandRunning: Messages.CoreGameSessionRecovery.launchCommandStillExists.localized
            case .processEnded: Messages.CoreGameSessionRecovery.originalProcessGone.localized
            case .confirmationRequired: Messages.CoreGameSessionRecovery.unverifiedGameExit.localized
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
        guard record == expected else { throw RuriError.message(Messages.CoreGameSessionRecovery.recordChanged) }
        let resolution: GameSessionInterruption.Resolution
        switch status(record) {
        case .finished: throw RuriError.message(Messages.CoreGameSessionRecovery.runCompleted)
        case .monitoring: throw RuriError.message(Messages.CoreGameSessionRecovery.monitorStillWriting)
        case .monitorUnconfirmed: throw RuriError.message(Messages.CoreGameSessionRecovery.monitorExitUnconfirmed)
        case .gameRunning: throw RuriError.message(Messages.CoreGameSessionRecovery.gameProcessStillExists)
        case .commandRunning: throw RuriError.message(Messages.CoreGameSessionRecovery.launchCommandStillExistsResolution)
        case .processEnded: resolution = .knownProcessEnded
        case .confirmationRequired:
            guard userConfirmedEnded else { throw RuriError.message(Messages.CoreGameSessionRecovery.gameExitUnconfirmed) }
            resolution = .userConfirmedEnded
        }
        let date = Date()
        record.controlEndpoint = nil; record.finalSnapshot = true
        record.revision = (record.revision) + 1
        if let exit = record.exit {
            let explanationMessage = Messages.CoreGameSessionRecovery.monitorInterruptedAfterExit
            let explanation = explanationMessage.localized
            if record.stage == .afterCommand && record.commandResults?.last?.phase != .after {
                record.commandResults = (record.commandResults ?? []) + [GameCommandResult(phase: .after, startedAt: record.updatedAt, endedAt: date, status: nil, cancelled: false, timedOut: false,
                    error: Messages.CoreGameSessionRecovery.interruptedUnknownCommandResult.localized, errorMessage: Messages.CoreGameSessionRecovery.interruptedUnknownCommandResult.recorded())]
            }
            record.commandIdentity = nil
            record.state = exit.stoppedByLauncher ? .stopped : exit.succeeded ? .succeeded : .failed
            record.stage = .finished; record.updatedAt = date
            if record.events.count < 512 { record.events.append(.init(id: UUID(), date: date, stage: .monitorRecovery, message: explanation, localizedMessage: explanationMessage.recorded())) }
            try GameHistoryStore.record(record, paths: paths)
            try? lease.clearReservation(session: record)
            return record
        }
        let explanationMessage = resolution == .knownProcessEnded
            ? Messages.CoreGameSessionRecovery.interruptedGameProcessGone
            : Messages.CoreGameSessionRecovery.interruptedUnverifiedGameExit
        let explanation = explanationMessage.localized
        record.interruption = .init(resolution: resolution, observedAt: date, previousStage: record.stage, explanation: explanation, explanationMessage: explanationMessage.recorded())
        record.state = .interrupted; record.stage = .monitorRecovery; record.updatedAt = date
        record.exit = nil
        if record.timing != nil { record.timing?.quality = .interrupted }
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: date, stage: .monitorRecovery, message: explanation, localizedMessage: explanationMessage.recorded())) }
        if record.nativeLogs == nil { record.nativeLogs = GameLogSources.references(paths: paths, session: record) }
        try GameHistoryStore.record(record, paths: paths)
        try? lease.clearReservation(session: record)
        return record
    }
}
