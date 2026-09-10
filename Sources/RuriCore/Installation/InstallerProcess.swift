import Foundation

/// Redirects helper output straight to disk so exit/cancellation cannot lose the
/// final error message to a racing pipe callback. Progress reads the same file.
actor InstallerProcess {
    private var process: Process?
    private var log: FileHandle?
    private var reader: FileHandle?
    private var monitor: Task<Void, Never>?
    private var continuation: CheckedContinuation<Int32, any Error>?
    private var cancelled = false
    private var output: (@Sendable (String) async -> Void)?
    private var tail = Data()
    func run(java: JavaRuntime, arguments: [String], directory: URL, logURL: URL, output: @Sendable @escaping (String) async -> Void) async throws -> Int32 {
        guard process == nil else { throw RuriError.message("安装程序已经在运行") }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        log = try FileHandle(forWritingTo: logURL); reader = try FileHandle(forReadingFrom: logURL)
        self.output = output; cancelled = false; tail = Data()
        defer { cleanup() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let process = Process()
                process.executableURL = URL(fileURLWithPath: java.path); process.arguments = arguments
                process.currentDirectoryURL = directory
                var environment = ProcessInfo.processInfo.environment
                for key in ["JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "CLASSPATH"] { environment.removeValue(forKey: key) }
                environment["JAVA_HOME"] = URL(fileURLWithPath: java.path).deletingLastPathComponent().deletingLastPathComponent().path
                process.environment = environment; process.standardOutput = log; process.standardError = log
                process.terminationHandler = { [weak self] process in
                    let status = process.terminationStatus
                    Task { await self?.finished(status) }
                }
                self.process = process
                do {
                    try process.run()
                    monitor = Task { [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                            await self?.reportProgress()
                        }
                    }
                } catch { self.process = nil; self.continuation = nil; continuation.resume(throwing: error) }
            }
        } onCancel: { Task { await self.cancel() } }
    }
    private func readOutput() -> String? {
        var last: String?
        while let data = try? reader?.read(upToCount: 64 * 1024), !data.isEmpty {
            tail.append(data)
            if tail.count > 64 * 1024 { tail.removeFirst(tail.count - 64 * 1024) }
            last = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).last.map(String.init)
        }
        return last
    }
    private func reportProgress() async { if let line = readOutput() { await output?(String(line.prefix(180))) } }
    private func cancel() { cancelled = true; if process?.isRunning == true { process?.terminate() } }
    private func finished(_ status: Int32) {
        _ = readOutput()
        let continuation = self.continuation; self.continuation = nil
        process = nil; monitor?.cancel()
        if cancelled { continuation?.resume(throwing: CancellationError()) } else { continuation?.resume(returning: status) }
    }
    private func cleanup() {
        monitor?.cancel(); monitor = nil
        try? log?.close(); try? reader?.close(); log = nil; reader = nil; process = nil; output = nil
    }
    func lastOutput() -> String { String(decoding: tail, as: UTF8.self) }
}
