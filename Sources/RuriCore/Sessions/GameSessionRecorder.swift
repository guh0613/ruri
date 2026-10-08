import Foundation
import RuriLocalization
import OSLog

/// The single runtime metadata writer. Byte capture, process supervision and
/// evidence discovery have their own lifetimes and do not run inside save().
@MainActor public final class GameSessionRecorder {
    package let writer: SessionRecordWriter
    public private(set) var record: GameSession { get { writer.record } set { writer.record = newValue } }
    public var directory: URL { writer.directory }
    public private(set) var hasHandedOff: Bool { get { writer.hasHandedOff } set { writer.hasHandedOff = newValue } }
    private let paths: LauncherPaths
    private var closed: Bool { get { writer.closed } set { writer.closed = newValue } }
    private var redactor: GameLogRedactor { writer.redactor }
    private var lease: GameRunLease?
    private var capturedOutput: [GameOutputCapture] = []
    private var artifactsCaptured = false
    private var savedCaptureCount = 0
    var onChange: (@Sendable (GameSession) -> Void)? { get { writer.onChange } set { writer.onChange = newValue } }
    var onCapture: (@Sendable (GameOutputCapture) -> Void)?

    public init(paths: LauncherPaths, instance: GameInstance, accountMode: String) throws {
        let instance = (try? instance.resolvingPersistedLaunchSettings(paths: paths)) ?? instance
        let memory = try? JVMHeapArguments.resolve(base: instance.frozenMemory ?? MemorySettings(maximumMB: instance.memoryMB).resolve(), arguments: ArgumentTokenizer.split(instance.extraJVMArguments))
        self.paths = paths
        try paths.validateBinding(instance)
        lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        let now = Date(), id = UUID()
        var record = GameSession(id: id, instanceID: instance.id, instanceName: instance.name, gameVersion: instance.gameVersion, loader: instance.loader.rawValue,
                             loaderVersion: instance.loaderVersion, memoryMB: memory?.maximumMB ?? instance.memoryMB,
                             operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, hostArchitecture: JavaRuntime.hostArchitecture,
                             accountMode: accountMode, ownerPID: ProcessInfo.processInfo.processIdentifier, createdAt: now, updatedAt: now,
                             state: .preparing, stage: .preparing, events: [], evidence: [])
        record.memory = memory
        record.launcherVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        record.debugLogging = instance.launchPresentation?.debugLogging == true
        record.gameDirectory = paths.game(instance.id)
        writer = try SessionRecordWriter(record: record, paths: paths)
        try transition(.preparing)
        try lease?.reserve(paths: paths, session: record)
    }

    public init(resuming sessionID: UUID, instanceID: UUID, paths: LauncherPaths, monitor: ProcessIdentity) throws {
        self.paths = paths
        lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID, ignoringSession: sessionID)
        var record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
        guard !record.state.isFinished, record.processID == nil, record.monitorIdentity == monitor,
              monitor.pid == ProcessInfo.processInfo.processIdentifier, monitor.isAlive else { throw RuriError.message(Messages.CoreGameSession.monitorCannotAdoptRun) }
        record.ownerPID = monitor.pid; record.updatedAt = Date()
        writer = try SessionRecordWriter(record: record, paths: paths)
        try save()
    }

    public func handoff(to monitor: ProcessIdentity) throws {
        guard record.processID == nil, !record.state.isFinished, !hasHandedOff else { throw RuriError.message(Messages.CoreGameSession.runCannotBeHandedToMonitor) }
        record.monitorIdentity = monitor; record.updatedAt = Date(); try save()
        hasHandedOff = true
        try close()
    }
    func acknowledgeHandoff(_ current: GameSession) {
        guard hasHandedOff, current.id == record.id, current.monitorIdentity == record.monitorIdentity else { return }
        record = current
    }
    func setControlEndpoint(_ endpoint: String) throws { record.controlEndpoint = endpoint; record.updatedAt = Date(); try save() }
    func checkpoint(_ timing: GameSessionTiming, activity: GameActivityTracking? = nil) {
        guard !record.state.isFinished, record.exit == nil else { return }
        record.timing = timing
        if let activity {
            record.activity = activity
            if let segment = activity.segments.last(where: { $0.target.kind == "world" }), case .world(let folder, let name) = segment.target {
                record.world = .init(folder: folder, name: name, lastPlayed: segment.startedAt, source: .detected)
            } else { record.world = nil }
        }
        record.updatedAt = Date(); record.revision = (record.revision) + 1
        do { try GameHistoryStore.checkpoint(record, paths: paths) } catch { storageWarning(error) }
        onChange?(record)
    }
    func makeOutputCapture() throws -> GameOutputCapture {
        let file = try LauncherPaths.safePath("console.log", within: directory)
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
    private func note(_ text: String) { do { try append(text) } catch { storageWarning(error) } }

    func setHostStatus(_ status: GameHostStatus) throws {
        guard !record.state.isFinished, record.host != status else { return }
        record.host = status; record.updatedAt = Date()
        try save(); note("[Ruri] \(status.summary)")
    }
    public func setNativeQuitSupported(_ supported: Bool) throws { record.nativeQuitSupported = supported; try save() }
    func recordNormalQuit(requestID: UUID, requestedAt: Date, accepted: Bool) throws {
        guard !record.state.isFinished else { return }
        let attempt = GameNormalQuitAttempt(requestID: requestID, requestedAt: requestedAt, processedAt: Date(), accepted: accepted)
        record.normalQuitAttempt = attempt; record.updatedAt = attempt.processedAt
        if accepted { record.stage = .quitting }
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: attempt.processedAt, stage: record.stage, message: attempt.explanation, localizedMessage: attempt.explanationMessage.recorded(redact: redactor.redact))) }
        try save()
    }
    public func started(processID: Int32) throws {
        record.processID = processID; record.gameIdentity = ProcessIdentity.read(processID)
        record.state = .running; try transition(.running)
    }
    func commandStarted(processID: Int32) throws { record.commandIdentity = ProcessIdentity.read(processID); record.updatedAt = Date(); try save() }
    func commandFinished(_ result: GameCommandResult) throws {
        record.commandResults = (record.commandResults ?? []) + [result]
        record.commandIdentity = nil; record.updatedAt = Date()
        try save(); note("[Ruri] " + result.summary)
    }

    /// Exit/timing are committed before any report reads or user post-command.
    func recordGameExit(_ exit: GameExit, timing: GameSessionTiming? = nil) throws {
        record.exit = exit
        if let timing { record.timing = timing }
        record.updatedAt = Date()
        record.nativeLogs = GameLogSources.references(paths: paths, session: record)
        try save()
    }

    func preserveEvidence(exit: GameExit, systemReportRoot: URL = GameSystemReportCollector.defaultRoot,
                          systemReportRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]) async {
        guard !artifactsCaptured else { return }
        artifactsCaptured = true
        // Successful ordinary runs own no duplicate output files. Native logs
        // stay in the game directory; only failures/debug runs preserve copies.
        guard exit.requiresAttention || record.debugLogging == true else { return }
        do { try saveCapturedOutput() } catch { storageWarning(error) }
        let paths = paths, redactor = redactor
        var snapshot = record
        snapshot.exit = exit
        let record = snapshot
        do {
            let files = try await Task.detached(priority: .utility) { try GameArtifactCollector.collect(paths: paths, session: record, exit: exit, redactor: redactor) }.value
            self.record.evidence = files; self.record.artifactState = .available; self.record.updatedAt = Date()
            try save()
        } catch { storageWarning(error) }
        do {
            let snapshot = record
            let files = try await Task.detached(priority: .utility) {
                let reports = try await GameSystemReportCollector.collectAfterExit(session: snapshot, root: systemReportRoot, retryDelays: systemReportRetryDelays)
                return try GameArtifactCollector.preserveSystemReports(reports.documents, paths: paths, session: snapshot, redactor: redactor)
            }.value
            if !files.isEmpty {
                self.record.evidence += files
                self.record.artifactState = .available
                try save()
            }
        } catch { storageWarning(error) }
    }

    public func finish(exit: GameExit) throws {
        guard !record.state.isFinished, !hasHandedOff else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        defer { try? close() }
        record.exit = exit; record.updatedAt = Date()
        if record.nativeLogs == nil { record.nativeLogs = GameLogSources.references(paths: paths, session: record) }
        record.state = exit.stoppedByLauncher ? .stopped : exit.succeeded ? .succeeded : .failed
        record.stage = .finished; record.controlEndpoint = nil
        if record.events.count < 512 { record.events.append(.init(id: UUID(), date: record.updatedAt, stage: .finished, message: exit.summary, localizedMessage: exit.summaryMessage.recorded(redact: redactor.redact))) }
        // Commit the result before touching diagnostic files. A broken output
        // sink cannot roll back playtime or the known process exit.
        var persistence = Result { try save() }
        if exit.requiresAttention || record.hasPostCommandFailure || record.debugLogging == true {
            do { try saveCapturedOutput() } catch { storageWarning(error) }
        }
        if !artifactsCaptured && (exit.requiresAttention || record.debugLogging == true) {
            do { record.evidence = try GameArtifactCollector.collect(paths: paths, session: record, exit: exit, redactor: redactor) }
            catch { storageWarning(error) }
            do {
                var budget = 6 * 1_048_576
                let reports = try GameSystemReportCollector.collect(session: record, budget: &budget)
                record.evidence += try GameArtifactCollector.preserveSystemReports(reports.documents, paths: paths, session: record, redactor: redactor)
            } catch { storageWarning(error) }
        }
        record.artifactState = FileManager.default.fileExists(atPath: directory.path) ? .available : .unavailable
        // History metadata only, read after the game has written its saves.
        record.applyWorldPlayed(start: exit.startedAt, end: exit.endedAt)
        record.finalSnapshot = true; record.updatedAt = Date()
        do { try save(); persistence = .success(()) } catch { storageWarning(error) }
        try close()
        try? GameSessionRetention.prune(paths: paths, instanceID: record.instanceID, keeping: record.id)
        try persistence.get()
    }

    public func fail(_ error: any Error, cancelled: Bool) throws {
        guard !record.state.isFinished, !hasHandedOff else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        defer { try? close() }
        record.failure = cancelled ? nil : redactor.redact(String(error.localizedDescription.prefix(32768)))
        record.failureMessage = cancelled ? nil : (error as? RuriError)?.localizedMessage?.recorded(limit: 32768, redact: redactor.redact)
        record.state = cancelled ? .cancelled : .failed; record.updatedAt = Date(); record.controlEndpoint = nil
        var persistence = Result { try save() }
        if !cancelled { do { try saveCapturedOutput() } catch { storageWarning(error) } }
        note("[Ruri] \(cancelled ? Messages.CoreGameSession.launchCancelled.localized : record.failure ?? Messages.CoreGameSession.launchFailed.localized)")
        record.finalSnapshot = true; record.artifactState = .available
        do { try save(); persistence = .success(()) } catch { storageWarning(error) }
        try close()
        try? GameSessionRetention.prune(paths: paths, instanceID: record.instanceID, keeping: record.id)
        try persistence.get()
    }

    public func close() throws {
        guard !closed else { return }
        defer { closed = true; lease = nil; capturedOutput = [] }
        do { try lease?.clearReservation(session: record) } catch { storageWarning(error) }
    }

    private func saveCapturedOutput() throws {
        let candidates = Array(capturedOutput.dropFirst(savedCaptureCount))
        let outputs = candidates.filter { record.debugLogging != true || $0.writeFailure != nil }
        guard !outputs.isEmpty else { savedCaptureCount = capturedOutput.count; return }
        record.outputTruncated = capturedOutput.contains { $0.writeFailure != nil || $0.isTruncated }
        let text = outputs.map { $0.snapshot(final: true, includeHead: true) }.joined(separator: "\n")
        guard !text.isEmpty else { savedCaptureCount = capturedOutput.count; return }
        try ensureArtifactDirectory()
        let tailFile = try LauncherPaths.safePath("console-tail.log", within: directory)
        let previous = FileManager.default.fileExists(atPath: tailFile.path) ? try GameSessionStore.readTail(tailFile, byteLimit: 1_048_576) : ""
        var data = Data(previous.utf8)
        if !data.isEmpty { data.append(10) }
        data.append(contentsOf: text.utf8)
        if data.count > 1_048_576 { record.outputTruncated = true }
        try data.suffix(1_048_576).write(to: tailFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tailFile.path)
        savedCaptureCount = capturedOutput.count
        for output in outputs {
            if let failure = output.writeFailure { note(Messages.MonitorLogging.writeFailed(failure).localized) }
        }
    }

    public func addSecrets(_ values: [String]) { writer.addSecrets(values) }
    public func redacted(_ text: String) -> String { writer.redacted(text) }
    func configureLogging(debug: Bool) throws { try writer.configureLogging(debug: debug) }
    public func append(_ text: String) throws { try writer.append(text) }
    public func transition(_ stage: GameSession.Stage, message: String? = nil) throws { try writer.transition(stage, message: message) }
    public func transition(_ stage: GameSession.Stage, message: LocalizedMessage) throws { try writer.transition(stage, message: message) }
    public func setJava(_ label: String) throws { try writer.setJava(label) }
    public func setMemory(_ memory: LaunchMemory) throws { try writer.setMemory(memory) }
    public func setTuning(_ tuning: JVMTuning) throws { try writer.setTuning(tuning) }
    public func setWorld(_ world: GameWorldPlay) throws { try writer.setWorld(world) }
    public func setDestination(_ destination: LaunchDestination) throws { try writer.setDestination(destination) }

    private func save() throws { try writer.save() }
    private func storageWarning(_ error: any Error) { writer.storageWarning(error) }
}
