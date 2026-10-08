import Foundation
import RuriLocalization

/// The single runtime metadata writer. Byte capture, process supervision and
/// evidence discovery have their own lifetimes and do not run inside save().
@MainActor package final class MonitorSessionRecorder {
    package let writer: SessionRecordWriter
    private(set) var record: GameSession { get { writer.record } set { writer.record = newValue } }
    var directory: URL { writer.directory }
    private var paths: any SessionPaths { writer.paths }
    private var redactor: GameLogRedactor { writer.redactor }
    private var releaseLease: ((GameSession) throws -> Void)?
    private var capturedOutput: [GameOutputCapture] = []
    private var artifactsCaptured = false
    private var savedCaptureCount = 0
    var onCapture: (@Sendable (GameOutputCapture) -> Void)?

    package init(writer: SessionRecordWriter, release: @escaping (GameSession) throws -> Void) {
        self.writer = writer; releaseLease = release
    }
    package convenience init(resuming sessionID: UUID, instanceID: UUID, paths: SessionLocationSnapshot, monitor: ProcessIdentity) throws {
        let lease = try SessionRunLease.resume(paths: paths, instanceID: instanceID, sessionID: sessionID, monitor: monitor)
        var record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
        record.ownerPID = monitor.pid; record.updatedAt = Date()
        let writer = try SessionRecordWriter(record: record, paths: paths)
        self.init(writer: writer) { record in try lease.clearReservation(session: record) }
        try writer.save()
    }

    func setControlEndpoint(_ endpoint: String) throws { record.controlEndpoint = endpoint; record.updatedAt = Date(); try writer.save() }
    func checkpoint(_ timing: GameSessionTiming, activity: GameActivityTracking? = nil) {
        guard !writer.closed, !writer.hasHandedOff, !record.state.isFinished, record.exit == nil else { return }
        record.timing = timing
        if let activity {
            record.activity = activity
            if let segment = activity.segments.last(where: { $0.target.kind == "world" }), case .world(let folder, let name) = segment.target {
                record.world = .init(folder: folder, name: name, lastPlayed: segment.startedAt, source: .detected)
            } else { record.world = nil }
        }
        record.updatedAt = Date(); record.revision = (record.revision) + 1
        do { try GameHistoryStore.checkpoint(record, paths: paths) } catch { writer.storageWarning(error) }
        writer.onChange?(record)
    }
    func makeOutputCapture() throws -> GameOutputCapture {
        let file = try SessionFileSystem.safePath("console.log", within: directory)
        if record.debugLogging == true && !FileManager.default.fileExists(atPath: file.path) {
            try ensureArtifactDirectory()
            guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw POSIXError(.EIO) }
        }
        return try GameOutputCapture(redactor: redactor, debugLogURL: record.debugLogging == true ? file : nil)
    }
    func retainOutput(_ output: GameOutputCapture) { capturedOutput.append(output); onCapture?(output) }

    private func ensureArtifactDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func prepareGame(directory: URL) {
        record.gameDirectory = directory
        record.logBaseline = GameLogSources.baseline(in: directory)
    }

    func setHostStatus(_ status: GameHostStatus) throws {
        guard !record.state.isFinished, record.host != status else { return }
        record.host = status; record.updatedAt = Date()
        try writer.save(); writer.note("[Ruri] \(status.summary)")
    }
    func setNativeQuitSupported(_ supported: Bool) throws { record.nativeQuitSupported = supported; try writer.save() }
    func recordNormalQuit(requestID: UUID, requestedAt: Date, accepted: Bool) throws {
        guard !record.state.isFinished else { return }
        let attempt = GameNormalQuitAttempt(requestID: requestID, requestedAt: requestedAt, processedAt: Date(), accepted: accepted)
        record.normalQuitAttempt = attempt; record.updatedAt = attempt.processedAt
        if accepted { record.stage = .quitting }
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: attempt.processedAt, stage: record.stage, message: attempt.explanation, localizedMessage: attempt.explanationMessage.recorded(redact: redactor.redact))) }
        try writer.save()
    }
    func started(processID: Int32) throws {
        record.processID = processID; record.gameIdentity = ProcessIdentity.read(processID)
        record.state = .running; try writer.transition(.running)
    }
    func commandStarted(processID: Int32) throws { record.commandIdentity = ProcessIdentity.read(processID); record.updatedAt = Date(); try writer.save() }
    func commandFinished(_ result: GameCommandResult) throws {
        record.commandResults = (record.commandResults ?? []) + [result]
        record.commandIdentity = nil; record.updatedAt = Date()
        try writer.save(); writer.note("[Ruri] " + result.summary)
    }

    /// Exit/timing are committed before any report reads or user post-command.
    func recordGameExit(_ exit: GameExit, timing: GameSessionTiming? = nil) throws {
        record.exit = exit
        if let timing { record.timing = timing }
        record.updatedAt = Date()
        record.nativeLogs = GameLogSources.references(paths: paths, session: record)
        try writer.save()
    }

    func preserveEvidence(exit: GameExit, systemReportRoot: URL = GameSystemReportCollector.defaultRoot,
                          systemReportRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]) async {
        guard !artifactsCaptured else { return }
        artifactsCaptured = true
        // Successful ordinary runs own no duplicate output files. Native logs
        // stay in the game directory; only failures/debug runs preserve copies.
        guard exit.requiresAttention || record.debugLogging == true else { return }
        do { try saveCapturedOutput() } catch { writer.storageWarning(error) }
        let paths = paths, redactor = redactor
        var snapshot = record
        snapshot.exit = exit
        let record = snapshot
        do {
            let files = try await Task.detached(priority: .utility) { try GameArtifactCollector.collect(paths: paths, session: record, exit: exit, redactor: redactor) }.value
            self.record.evidence = files; self.record.artifactState = .available; self.record.updatedAt = Date()
            try writer.save()
        } catch { writer.storageWarning(error) }
        do {
            let snapshot = record
            let files = try await Task.detached(priority: .utility) {
                let reports = try await GameSystemReportCollector.collectAfterExit(session: snapshot, root: systemReportRoot, retryDelays: systemReportRetryDelays)
                return try GameArtifactCollector.preserveSystemReports(reports.documents, paths: paths, session: snapshot, redactor: redactor)
            }.value
            if !files.isEmpty {
                self.record.evidence += files
                self.record.artifactState = .available
                try writer.save()
            }
        } catch { writer.storageWarning(error) }
    }

    func finish(exit: GameExit) throws {
        try writer.requireWritable()
        guard !record.state.isFinished else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        defer { try? close() }
        record.exit = exit; record.updatedAt = Date()
        if record.nativeLogs == nil { record.nativeLogs = GameLogSources.references(paths: paths, session: record) }
        record.state = exit.stoppedByLauncher ? .stopped : exit.succeeded ? .succeeded : .failed
        record.stage = .finished; record.controlEndpoint = nil
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: record.updatedAt, stage: .finished, message: exit.summary, localizedMessage: exit.summaryMessage.recorded(redact: redactor.redact))) }
        // Commit the result before touching diagnostic files. A broken output
        // sink cannot roll back playtime or the known process exit.
        var persistence = Result { try writer.save() }
        if exit.requiresAttention || record.hasPostCommandFailure || record.debugLogging == true {
            do { try saveCapturedOutput() } catch { writer.storageWarning(error) }
        }
        if !artifactsCaptured && (exit.requiresAttention || record.debugLogging == true) {
            do { record.evidence = try GameArtifactCollector.collect(paths: paths, session: record, exit: exit, redactor: redactor) }
            catch { writer.storageWarning(error) }
            do {
                var budget = 6 * 1_048_576
                let reports = try GameSystemReportCollector.collect(session: record, budget: &budget)
                record.evidence += try GameArtifactCollector.preserveSystemReports(reports.documents, paths: paths, session: record, redactor: redactor)
            } catch { writer.storageWarning(error) }
        }
        record.artifactState = FileManager.default.fileExists(atPath: directory.path) ? .available : .unavailable
        // History metadata only, read after the game has written its saves.
        record.applyWorldPlayed(start: exit.startedAt, end: exit.endedAt)
        record.finalSnapshot = true; record.updatedAt = Date()
        do { try writer.save(); persistence = .success(()) } catch { writer.storageWarning(error) }
        try? SessionArtifactRetention.prune(paths: paths, instanceID: record.instanceID, keeping: record.id)
        try close()
        try persistence.get()
    }

    func fail(_ error: any Error, cancelled: Bool) throws {
        let persistence = try writer.recordFailure(error, cancelled: cancelled) { try saveCapturedOutput() }
        defer { try? close() }
        try? SessionArtifactRetention.prune(paths: paths, instanceID: record.instanceID, keeping: record.id)
        try close()
        try persistence.get()
    }

    func close() throws {
        guard !writer.closed else { return }
        defer { writer.closed = true; releaseLease = nil; capturedOutput = [] }
        do { try releaseLease?(record) } catch { writer.storageWarning(error) }
    }

    private func saveCapturedOutput() throws {
        let candidates = Array(capturedOutput.dropFirst(savedCaptureCount))
        let outputs = candidates.filter { record.debugLogging != true || $0.writeFailure != nil }
        guard !outputs.isEmpty else { savedCaptureCount = capturedOutput.count; return }
        record.outputTruncated = capturedOutput.contains { $0.writeFailure != nil || $0.isTruncated }
        let text = outputs.map { $0.snapshot(final: true, includeHead: true) }.joined(separator: "\n")
        guard !text.isEmpty else { savedCaptureCount = capturedOutput.count; return }
        try ensureArtifactDirectory()
        let tailFile = try SessionFileSystem.safePath("console-tail.log", within: directory)
        let previous = FileManager.default.fileExists(atPath: tailFile.path) ? try GameSessionStore.readTail(tailFile, byteLimit: 1_048_576) : ""
        var data = Data(previous.utf8)
        if !data.isEmpty { data.append(10) }
        data.append(contentsOf: text.utf8)
        if data.count > 1_048_576 { record.outputTruncated = true }
        try data.suffix(1_048_576).write(to: tailFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tailFile.path)
        savedCaptureCount = capturedOutput.count
        for output in outputs {
            if let failure = output.writeFailure { writer.note(Messages.MonitorLogging.writeFailed(failure).localized) }
        }
    }
}
