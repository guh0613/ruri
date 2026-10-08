import Foundation
import RuriLocalization
import OSLog

/// One revisioned writer shared by launch preparation and runtime ownership.
/// It does not acquire leases, execute processes, or retain process output.
@MainActor package final class SessionRecordWriter {
    package var record: GameSession
    package let paths: any SessionPaths
    package let directory: URL
    package var hasHandedOff = false
    package var closed = false
    package var redactor = GameLogRedactor()
    package var onChange: (@Sendable (GameSession) -> Void)?
    private var warnedAboutStorage = false

    package init(record: GameSession, paths: any SessionPaths) throws {
        self.record = record; self.paths = paths
        directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
    }
    package func addSecrets(_ values: [String]) { redactor.addSecrets(values) }
    package func redacted(_ text: String) -> String { redactor.redact(text) }

    package func configureLogging(debug: Bool) throws {
        try requireWritable()
        guard record.debugLogging != debug else { return }
        record.debugLogging = debug; try save()
    }
    package func append(_ text: String) throws {
        guard !closed else { throw RuriError.message(Messages.CoreGameSession.runLogClosed) }
        try GameSessionEventStore.append(redactor.redact(text), sessionID: record.id, paths: paths)
    }
    package func transition(_ stage: GameSession.Stage, message: String? = nil) throws {
        try transition(stage, message: message.map(LocalizedMessage.verbatim) ?? stage.message)
    }
    package func transition(_ stage: GameSession.Stage, message: LocalizedMessage) throws {
        try requireWritable()
        guard !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        record.stage = stage; record.updatedAt = Date()
        let descriptor = message.recorded(redact: redactor.redact)
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: record.updatedAt, stage: stage, message: descriptor.fallback, localizedMessage: descriptor)) }
        try save()
    }
    package func setJava(_ label: String) throws { try requireWritable(); record.java = label; try save() }
    package func setMemory(_ memory: LaunchMemory) throws {
        try requireWritable()
        guard record.processID == nil, !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.memoryChangeAfterLaunch) }
        record.memory = memory; record.memoryMB = memory.maximumMB; try save()
    }
    package func setTuning(_ tuning: JVMTuning) throws {
        try requireWritable()
        guard record.processID == nil, !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.memoryChangeAfterLaunch) }
        record.tuning = tuning; try save()
    }
    package func setWorld(_ world: GameWorldPlay) throws {
        try requireWritable()
        guard !record.state.isFinished, world.isValid else { return }
        record.world = world; try save()
    }
    package func setDestination(_ destination: LaunchDestination) throws {
        try requireWritable()
        guard !record.state.isFinished else { return }
        record.destination = destination; try save()
    }
    package func requireWritable() throws {
        guard !closed, !hasHandedOff else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
    }
    /// Return the persistence result so each owner can finish cleanup and release
    /// its lease before propagating an I/O failure. Evidence is best effort.
    package func recordFailure(_ error: any Error, cancelled: Bool, preserveOutput: () throws -> Void = {}) throws -> Result<Void, any Error> {
        try requireWritable()
        guard !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        record.failure = cancelled ? nil : redactor.redact(String(error.localizedDescription.prefix(32768)))
        record.failureMessage = cancelled ? nil : (error as? RuriError)?.localizedMessage?.recorded(limit: 32768, redact: redactor.redact)
        record.state = cancelled ? .cancelled : .failed; record.controlEndpoint = nil
        var persistence = Result { try save() }
        if !cancelled { do { try preserveOutput() } catch { storageWarning(error) } }
        note("[Ruri] \(cancelled ? Messages.CoreGameSession.launchCancelled.localized : record.failure ?? Messages.CoreGameSession.launchFailed.localized)")
        record.finalSnapshot = true; record.artifactState = .available
        do { try save(); persistence = .success(()) } catch { storageWarning(error) }
        return persistence
    }
    package func note(_ text: String) { do { try append(text) } catch { storageWarning(error) } }
    package func save() throws {
        try requireWritable()
        record.revision = (record.revision) + 1
        record.updatedAt = Date()
        do { try GameHistoryStore.record(record, paths: paths) }
        catch { storageWarning(error); throw error }
        onChange?(record)
    }
    package func storageWarning(_ error: any Error) {
        let text = redactor.redact(error.localizedDescription)
        Logger(subsystem: "dev.ruri", category: "monitor").error("\(text, privacy: .private)")
        guard !warnedAboutStorage else { return }
        warnedAboutStorage = true
        try? GameSessionEventStore.append(Messages.SessionRuntime.storageWarning(text).localized, sessionID: record.id, paths: paths)
    }
}
