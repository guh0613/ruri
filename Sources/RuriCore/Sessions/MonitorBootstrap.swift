import Foundation
import Darwin

/// The only credential-bearing monitor transport is an inherited pipe. Its
/// bounded write happens off the UI actor and cannot hang launch indefinitely.
enum MonitorBootstrap {
    static func send(_ data: Data, to handle: FileHandle) async throws {
        let fd = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 3)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        let work = Task.detached(priority: .userInitiated) {
            defer { Darwin.close(fd) }
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { throw POSIXError(.EIO) }
            // Avoid SIGPIPE on this writer thread without changing the game's
            // inherited process-wide signal disposition.
            var set = sigset_t(), old = sigset_t()
            sigemptyset(&set); sigaddset(&set, SIGPIPE)
            pthread_sigmask(SIG_BLOCK, &set, &old)
            defer {
                var pending = sigset_t(); sigpending(&pending)
                if sigismember(&pending, SIGPIPE) != 0 { var signal: Int32 = 0; sigwait(&set, &signal) }
                pthread_sigmask(SIG_SETMASK, &old, nil)
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    try Task.checkCancellation()
                    guard ContinuousClock.now < deadline else { throw POSIXError(.ETIMEDOUT) }
                    let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count > 0 { offset += count }
                    else if count < 0 && errno == EINTR { continue }
                    else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                        var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        _ = poll(&poller, 1, 100)
                    } else { throw POSIXError(.EPIPE) }
                }
            }
        }
        // Ownership has already transferred. Complete the bounded bootstrap
        // even if the launcher task is cancelled, rather than sending half JSON.
        try await work.value
    }
}
