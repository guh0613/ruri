import Foundation
import Darwin

/// Serializes pipe reads and the final drain. A mod's helper may inherit stdout,
/// so finishing the game must not wait for every descendant to close the pipe.
final class ProcessOutputReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.ruri.game-output", qos: .utility, autoreleaseFrequency: .workItem)
    private let descriptor: Int32
    private let source: DispatchSourceRead
    private let receive: @Sendable (Data) -> Void
    private var closed = false // Accessed only on queue.

    init(handle: FileHandle, receive: @escaping @Sendable (Data) -> Void) throws {
        let descriptor = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 3)
        guard descriptor >= 0 else { throw POSIXError(.EMFILE) }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            Darwin.close(descriptor); throw POSIXError(code)
        }
        self.descriptor = descriptor; self.receive = receive
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.drain(limit: 1_048_576) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    func finish(_ completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            // Parent output is finite once it has exited; cap a still-writing
            // descendant so it cannot prevent the launch session from finishing.
            drain(limit: 16 * 1_048_576)
            close()
            completion()
        }
    }

    private func drain(limit: Int) {
        guard !closed else { return }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var consumed = 0
        while consumed < limit {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 { autoreleasepool { receive(Data(buffer.prefix(count))) }; consumed += count }
            else if count == 0 { close(); return }
            else if errno == EINTR { continue }
            else if errno == EAGAIN || errno == EWOULDBLOCK { return }
            else { close(); return }
        }
    }
    private func close() {
        guard !closed else { return }
        closed = true; source.cancel()
    }
}
