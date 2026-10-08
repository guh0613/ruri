import Foundation
import RuriLocalization

/// Preparation owns the launch lease until the durable monitor handoff.
@MainActor public final class GameSessionRecorder {
    package let writer: SessionRecordWriter
    public private(set) var record: GameSession { get { writer.record } set { writer.record = newValue } }
    public var directory: URL { writer.directory }
    public private(set) var hasHandedOff: Bool { get { writer.hasHandedOff } set { writer.hasHandedOff = newValue } }
    private let paths: LauncherPaths
    private var lease: GameRunLease?
    private var redactor: GameLogRedactor { writer.redactor }
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
    public func fail(_ error: any Error, cancelled: Bool) throws {
        guard !record.state.isFinished, !hasHandedOff else { throw RuriError.message(Messages.CoreGameSession.runAlreadyFinished) }
        defer { try? close() }
        record.failure = cancelled ? nil : redactor.redact(String(error.localizedDescription.prefix(32768)))
        record.failureMessage = cancelled ? nil : (error as? RuriError)?.localizedMessage?.recorded(limit: 32768, redact: redactor.redact)
        record.state = cancelled ? .cancelled : .failed; record.updatedAt = Date(); record.controlEndpoint = nil
        var persistence = Result { try save() }
        note("[Ruri] \(cancelled ? Messages.CoreGameSession.launchCancelled.localized : record.failure ?? Messages.CoreGameSession.launchFailed.localized)")
        record.finalSnapshot = true; record.artifactState = .available
        do { try save(); persistence = .success(()) } catch { storageWarning(error) }
        try close()
        try? GameSessionRetention.prune(paths: paths, instanceID: record.instanceID, keeping: record.id)
        try persistence.get()
    }

    public func close() throws {
        guard !writer.closed else { return }
        defer { writer.closed = true; lease = nil }
        do { try lease?.clearReservation(session: record) } catch { storageWarning(error) }
    }
    private func note(_ text: String) { do { try append(text) } catch { storageWarning(error) } }
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
