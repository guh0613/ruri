import Foundation
import Darwin

/// One ephemeral socket per game. No launchd registration, network listener,
/// credential file or permanent daemon is needed to reconnect a launcher.
final class MonitorServiceTransport: @unchecked Sendable {
    let endpoint: String
    private let root: String
    private let queue = DispatchQueue(label: "dev.ruri.monitor-server", qos: .utility, autoreleaseFrequency: .workItem)
    private let listener: DispatchSourceRead
    private let changes: DispatchSourceUserDataAdd
    private var peers: [Int32: MonitorSocketPeer] = [:]
    private var session: GameSession
    private var capture: GameOutputCapture?
    private var lastOutput: GameOutputSnapshot?
    private var publishScheduled = false
    private var closed = false
    private let control: @MainActor @Sendable (MonitorControlRequest) -> Bool

    init(session: GameSession, control: @escaping @MainActor @Sendable (MonitorControlRequest) -> Bool) throws {
        self.session = session; self.control = control
        var template = Array("/tmp/ruri-monitor-XXXXXX".utf8CString)
        guard let directory = mkdtemp(&template) else { throw POSIXError(.EIO) }
        root = String(cString: directory); endpoint = root + "/control.sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { rmdir(root); throw POSIXError(.EMFILE) }
        do {
            try MonitorSocket.configure(fd)
            var address = try MonitorSocket.address(endpoint)
            let length = socklen_t(address.sun_len)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, length) }
            }
            guard result == 0, listen(fd, 8) == 0 else { throw POSIXError(.EIO) }
            _ = chmod(endpoint, S_IRUSR | S_IWUSR)
        } catch { Darwin.close(fd); unlink(endpoint); rmdir(root); throw error }
        listener = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        changes = DispatchSource.makeUserDataAddSource(queue: queue)
        listener.setEventHandler { [weak self] in self?.acceptClients(fd) }
        listener.setCancelHandler { Darwin.close(fd) }
        changes.setEventHandler { [weak self] in self?.scheduleOutput() }
        listener.resume(); changes.resume()
    }

    func update(_ record: GameSession) {
        queue.async { [self] in
            guard !closed else { return }
            session = record
            for peer in Array(peers.values) {
                guard let subscription = peer.subscription else { continue }
                reply(to: peer, request: subscription, output: subscription.output ? lastOutput : nil)
            }
        }
    }
    func setCapture(_ capture: GameOutputCapture) {
        queue.async { [self] in
            self.capture?.observe(nil); self.capture = capture; lastOutput = nil
            for peer in peers.values { peer.lastOutput = nil }
            updateCaptureObservation()
            if peers.values.contains(where: { $0.subscription?.output == true }) { scheduleOutput() }
        }
    }
    func close() {
        queue.sync {
            guard !closed else { return }
            closed = true; capture?.observe(nil)
            for peer in Array(peers.values) { peer.close() }
            peers.removeAll(); listener.cancel(); changes.cancel()
            unlink(endpoint); rmdir(root)
        }
    }
    private func acceptClients(_ descriptor: Int32) {
        while !closed {
            let fd = accept(descriptor, nil, nil)
            guard fd >= 0 else { return }
            guard peers.count < 8, MonitorSocket.sameUser(fd), (try? MonitorSocket.configure(fd)) != nil else { Darwin.close(fd); continue }
            let peer = MonitorSocketPeer(descriptor: fd, queue: queue)
            peers[fd] = peer
            peer.onFrame = { [weak self, weak peer] data in
                guard let self, let peer else { return }
                self.receive(data, from: peer)
            }
            peer.onClose = { [weak self] in self?.peers.removeValue(forKey: fd); self?.updateCaptureObservation() }
            peer.start()
            queue.asyncAfter(deadline: .now() + 5) { [weak peer] in
                if peer?.subscription == nil { peer?.close() }
            }
        }
    }
    private func receive(_ data: Data, from peer: MonitorSocketPeer) {
        guard !peer.handledRequest, data.count <= 4096,
              let request = try? JSONDecoder().decode(MonitorControlRequest.self, from: data), request.version == 1,
              request.sessionID == session.id, request.monitor == session.monitorIdentity else { peer.close(); return }
        peer.handledRequest = true
        switch request.command {
        case .subscribe:
            peer.subscription = request
            updateCaptureObservation()
            if request.output { lastOutput = capture?.snapshotValue(final: true) }
            reply(to: peer, request: request, output: request.output ? lastOutput : nil)
        case .snapshot:
            reply(to: peer, request: request, output: capture?.snapshotValue(final: true))
        case .status:
            reply(to: peer, request: request)
        case .stop, .quit:
            Task { @MainActor [weak self, weak peer] in
                guard let self else { return }
                let accepted = control(request)
                queue.async { [weak self, weak peer] in
                    guard let self, let peer else { return }
                    reply(to: peer, request: request, accepted: accepted)
                }
            }
        }
    }
    private func reply(to peer: MonitorSocketPeer, request: MonitorControlRequest, output: GameOutputSnapshot? = nil, accepted: Bool? = nil) {
        var delta = output
        if request.command == .subscribe, let output {
            if let previous = peer.lastOutput, output.revision >= previous.revision, output.text.hasPrefix(previous.text) {
                delta = .init(revision: output.revision, text: String(output.text.dropFirst(previous.text.count)), truncated: output.truncated,
                              finished: output.finished, isReplacement: false)
            }
            peer.lastOutput = output
        }
        if let data = try? JSONEncoder().encode(MonitorUpdate(requestID: request.id, sessionID: session.id, session: session, output: delta, accepted: accepted)) { peer.send(data) }
        else { peer.close() }
    }
    private func updateCaptureObservation() {
        if peers.values.contains(where: { $0.subscription?.output == true }) {
            capture?.observe { [weak self] in self?.changes.add(data: 1) }
        } else { capture?.observe(nil); lastOutput = nil }
    }
    private func scheduleOutput() {
        guard !closed, !publishScheduled, peers.values.contains(where: { $0.subscription?.output == true }) else { return }
        publishScheduled = true
        // Not a repeating timer: nothing is scheduled when output is quiet or
        // nobody is looking. A burst generates at most one preview per second.
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            publishScheduled = false
            guard !closed, let capture, peers.values.contains(where: { $0.subscription?.output == true }) else { return }
            let output = capture.snapshotValue(final: true)
            guard lastOutput != output else { return }
            lastOutput = output
            for peer in Array(peers.values) {
                if let request = peer.subscription, request.output { reply(to: peer, request: request, output: output) }
            }
        }
    }
}
