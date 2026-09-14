import Foundation
import RuriLocalization

@MainActor
public final class GameProcess {
    private var process: Process?
    private var pipe: Pipe?
    private var reader: ProcessOutputReader?
    private var pending = Data()
    private var formatter = GameLogFormatter()
    private var secrets: [String] = []
    private var output: (@MainActor @Sendable (String) -> Void)?
    private var onExit: (@MainActor @Sendable (GameExit) -> Void)?
    private var stopRequested = false
    private var normalQuitRequested = false
    private var nativeQuitSupported = false
    private var identity: ProcessIdentity?
    private var hostConnection: GameHostConnection?
    private var onHostStatus: (@MainActor @Sendable (GameHostStatus) -> Void)?
    public private(set) var hostStatus: GameHostStatus?
    public var isRunning: Bool { process?.isRunning ?? false }
    public var processIdentifier: Int32? { process?.processIdentifier }
    public init() {}
    public func start(plan: LaunchPlan, secrets: [String] = [], output: @escaping @MainActor @Sendable (String) -> Void, onExit: @escaping @MainActor @Sendable (GameExit) -> Void) throws {
        try start(plan: plan, secrets: secrets, capture: nil, sessionID: UUID(), hostExecutable: nil, hostStatus: { _ in }, output: output, onExit: onExit)
    }
    func start(plan: LaunchPlan, capture: GameOutputCapture, sessionID: UUID = UUID(), hostExecutable: URL? = nil, hostStatus: @escaping @MainActor @Sendable (GameHostStatus) -> Void = { _ in }, onExit: @escaping @MainActor @Sendable (GameExit) -> Void) throws {
        try start(plan: plan, secrets: [], capture: capture, sessionID: sessionID, hostExecutable: hostExecutable, hostStatus: hostStatus, output: { _ in }, onExit: onExit)
    }
    private func start(plan: LaunchPlan, secrets: [String], capture: GameOutputCapture?, sessionID: UUID, hostExecutable: URL?, hostStatus: @escaping @MainActor @Sendable (GameHostStatus) -> Void, output: @escaping @MainActor @Sendable (String) -> Void, onExit: @escaping @MainActor @Sendable (GameExit) -> Void) throws {
        guard self.process == nil else { throw RuriError.message(Messages.CoreLaunch.gameAlreadyRunning) }
        self.secrets = (secrets + plan.environmentRedactions).filter { $0.count > 3 }; self.output = output; self.onExit = onExit; pending = Data(); formatter = GameLogFormatter()
        stopRequested = false
        normalQuitRequested = false; nativeQuitSupported = plan.nativeQuitSupported == true; identity = nil
        let startedAt = Date()
        let startedClock = ContinuousClock.now
        let process = Process(); let pipe = Pipe()
        let (host, initialStatus) = GameHostLaunch.prepare(plan, sessionID: sessionID, host: hostExecutable)
        self.onHostStatus = hostStatus
        self.hostStatus = plan.host == nil ? nil : initialStatus
        let connection = try host.map { launch in
            try GameHostConnection(request: launch.request) { [weak self] event in
                DispatchQueue.main.async { self?.receiveHostEvent(event) }
            }
        }
        process.executableURL = plan.processExecutable; process.arguments = plan.processArguments; process.currentDirectoryURL = plan.directory; process.environment = plan.environment
        process.standardOutput = pipe; process.standardError = pipe
        process.standardInput = connection?.input ?? FileHandle.nullDevice
        if let host { process.executableURL = host.executable; process.arguments = host.arguments }
        let reader = try ProcessOutputReader(handle: pipe.fileHandleForReading) { [weak self] data in
            if let capture { capture.receive(data) }
            else { DispatchQueue.main.async { autoreleasepool { self?.receive(data) } } }
        }
        process.terminationHandler = { [weak self, reader, connection] process in
            let status = process.terminationStatus
            let reason: GameExit.Reason = process.terminationReason == .uncaughtSignal ? .signal : .exit
            let processID = process.processIdentifier
            let endedAt = Date()
            let duration = startedClock.duration(to: .now).components
            let elapsed = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            let finishOutput: @Sendable () -> Void = { [weak self] in
                reader.finish { [weak self] in
                    capture?.finish()
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if !self.pending.isEmpty { self.emit(String(decoding: self.pending, as: UTF8.self)); self.pending.removeAll() }
                        for line in self.formatter.flush() { self.redactAndSend(line) }
                        if var host = self.hostStatus, host.backend == .native, !host.jvmStarted, host.failure == nil, !self.stopRequested {
                            host.failure = "transport"; self.hostStatus = host; self.onHostStatus?(host)
                        }
                        let result = GameExit(status: status, reason: reason, processID: processID, startedAt: startedAt, endedAt: endedAt, stopRequested: self.stopRequested, durationSeconds: elapsed, normalQuitRequested: self.normalQuitRequested ? true : nil)
                        let callback = self.onExit
                        self.process = nil; self.pipe = nil; self.reader = nil; self.hostConnection = nil; self.onHostStatus = nil; self.onExit = nil; self.output = nil; self.secrets = []
                        callback?(result)
                    }
                }
            }
            if let connection { connection.finish(finishOutput) } else { finishOutput() }
        }
        do {
            try process.run()
            self.process = process; self.pipe = pipe; self.reader = reader; self.hostConnection = connection
            identity = ProcessIdentity.read(process.processIdentifier)
            if let status = self.hostStatus { hostStatus(status) }
            do { try connection?.started(pid: process.processIdentifier) }
            catch {
                connection?.close()
                receiveHostEvent(.init(version: 1, sessionID: sessionID, pid: process.processIdentifier, event: "failed", code: "transport", value: nil))
                process.terminate()
            }
        } catch {
            connection?.close(); reader.finish {}
            self.output = nil; self.onExit = nil; self.onHostStatus = nil
            throw error
        }
    }
    private func receiveHostEvent(_ event: GameHostEvent) {
        guard var status = hostStatus, process?.processIdentifier == event.pid else { return }
        switch event.event {
        case "ready": break
        case "jvmStarting": status.jvmStarted = true
        case "windowReady":
            guard status.backend == .native, status.jvmStarted else { return }
            status.windowReadyAt = status.windowReadyAt ?? Date()
        case "fullscreen":
            guard status.windowReadyAt != nil, let value = event.value else { return }
            status.fullscreen = value
        case "fallback":
            guard !status.jvmStarted else { return }
            status.backend = .java; status.fallback = event.code
        case "failed": status.failure = event.code ?? "request"
        default: return
        }
        guard status != hostStatus else { return }
        hostStatus = status; onHostStatus?(status)
    }
    public func stop() {
        guard let process, process.isRunning else { return }
        stopRequested = true
        process.terminate()
    }
    @discardableResult public func requestNormalQuit() -> Bool {
        guard nativeQuitSupported, process?.isRunning == true, let identity else { return false }
        let accepted = NativeGameQuit.request(identity)
        if accepted { normalQuitRequested = true }
        return accepted
    }
    private func receive(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            emit(String(decoding: pending[..<newline], as: UTF8.self)); pending.removeSubrange(...newline)
        }
        if pending.count > 1024 * 1024 { emit(Messages.CoreLaunch.longLogLineOmitted.localized); pending.removeAll() }
    }
    private func emit(_ input: String) {
        for line in formatter.consume(input) { redactAndSend(line) }
    }
    private func redactAndSend(_ input: String) {
        var text = input
        for secret in secrets { text = text.replacingOccurrences(of: secret, with: "<redacted>") }
        output?(text)
    }
}
