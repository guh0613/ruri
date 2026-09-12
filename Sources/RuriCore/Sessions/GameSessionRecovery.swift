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
            case .finished: Messages.CoreGameSessionRecovery.titleText1.localized
            case .monitoring: Messages.CoreGameSessionRecovery.titleText2.localized
            case .monitorUnconfirmed: Messages.CoreGameSessionRecovery.titleText3.localized
            case .gameRunning: Messages.CoreGameSessionRecovery.titleText4.localized
            case .commandRunning: Messages.CoreGameSessionRecovery.titleText5.localized
            case .processEnded: Messages.CoreGameSessionRecovery.titleText6.localized
            case .confirmationRequired: Messages.CoreGameSessionRecovery.titleText7.localized
            }
        }
        public var explanation: String {
            switch self {
            case .finished: Messages.CoreGameSessionRecovery.explanationText1.localized
            case .monitoring: Messages.CoreGameSessionRecovery.explanationText2.localized
            case .monitorUnconfirmed: Messages.CoreGameSessionRecovery.explanationText3.localized
            case .gameRunning: Messages.CoreGameSessionRecovery.explanationText4.localized
            case .commandRunning: Messages.CoreGameSessionRecovery.explanationText5.localized
            case .processEnded: Messages.CoreGameSessionRecovery.explanationText6.localized
            case .confirmationRequired: Messages.CoreGameSessionRecovery.explanationText7.localized
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
        guard record == expected else { throw RuriError.message(Messages.CoreGameSessionRecovery.recordText1) }
        let resolution: GameSessionInterruption.Resolution
        switch status(record) {
        case .finished: throw RuriError.message(Messages.CoreGameSessionRecovery.resolutionText1)
        case .monitoring: throw RuriError.message(Messages.CoreGameSessionRecovery.resolutionText2)
        case .monitorUnconfirmed: throw RuriError.message(Messages.CoreGameSessionRecovery.resolutionText3)
        case .gameRunning: throw RuriError.message(Messages.CoreGameSessionRecovery.resolutionText4)
        case .commandRunning: throw RuriError.message(Messages.CoreGameSessionRecovery.resolutionText5)
        case .processEnded: resolution = .knownProcessEnded
        case .confirmationRequired:
            guard userConfirmedEnded else { throw RuriError.message(Messages.CoreGameSessionRecovery.resolutionText6) }
            resolution = .userConfirmedEnded
        }
        let date = Date()
        if let exit = record.exit {
            let explanationMessage = Messages.CoreGameSessionRecovery.explanationText8
            let explanation = explanationMessage.localized
            if record.stage == .afterCommand && record.commandResults?.last?.phase != .after {
                record.commandResults = (record.commandResults ?? []) + [GameCommandResult(phase: .after, startedAt: record.updatedAt, endedAt: date, status: nil, cancelled: false, timedOut: false,
                    error: Messages.CoreGameSessionRecovery.explanationText9.localized, errorMessage: Messages.CoreGameSessionRecovery.explanationText9.recorded())]
            }
            record.commandIdentity = nil
            record.state = exit.stoppedByLauncher ? .stopped : exit.succeeded ? .succeeded : .failed
            record.stage = .finished; record.updatedAt = date
            if record.events.count < 512 { record.events.append(.init(id: UUID(), date: date, stage: .monitorRecovery, message: explanation, localizedMessage: explanationMessage.recorded())) }
            let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
            try JSONEncoder().encode(record).write(to: directory.appendingPathComponent("session.json"), options: .atomic)
            try GamePlaytimeStore.record(record, paths: paths)
            try? lease.clearReservation(session: record)
            try? appendRecoveryLog(explanation, date: date, paths: paths, record: record)
            return record
        }
        let explanationMessage = resolution == .knownProcessEnded
            ? Messages.CoreGameSessionRecovery.explanationText10
            : Messages.CoreGameSessionRecovery.explanationText11
        let explanation = explanationMessage.localized
        record.interruption = .init(resolution: resolution, observedAt: date, previousStage: record.stage, explanation: explanation, explanationMessage: explanationMessage.recorded())
        record.state = .interrupted; record.stage = .monitorRecovery; record.updatedAt = date
        record.exit = nil
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: date, stage: .monitorRecovery, message: explanation, localizedMessage: explanationMessage.recorded())) }
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
        guard fd >= 0 else { throw RuriError.message(Messages.CoreGameSessionRecovery.fdText1) }
        defer { Darwin.close(fd) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { throw RuriError.message(Messages.CoreGameSessionRecovery.attributesText1) }
        let data = Data(("\n[Ruri] \(date.ISO8601Format()) \(text)\n").utf8)
        guard data.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == data.count else { throw RuriError.message(Messages.CoreGameSessionRecovery.dataText1) }
    }
}
