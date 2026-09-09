import Foundation

struct DownloadResumeState: Codable, Sendable {
    let identity: String
    let etag: String?
    let lastModified: String?
    var sourceURL: String? = nil
    var validator: String? {
        // Some Mojang/Azure responses expose a bare, unquoted ETag. It is not a
        // valid strong If-Range validator; use Last-Modified for those responses.
        etag.flatMap { $0.hasPrefix("\"") && $0.hasSuffix("\"") && $0.count >= 2 ? $0 : nil } ?? lastModified
    }
}

struct DownloadFailure: LocalizedError, Sendable {
    let message: String
    var discardPartial = false
    var errorDescription: String? { message }
}

public struct DownloadTransferProgress: Sendable {
    public let receivedBytes: Int64
    public let totalBytes: Int64?
    public let resumedBytes: Int64
}

struct HTTPContentRange: Equatable {
    let start: Int64
    let end: Int64
    let total: Int64
    init(_ value: String) throws {
        let pieces = value.split(separator: " ")
        guard pieces.count == 2, pieces[0] == "bytes" else { throw DownloadFailure(message: "服务器返回了无效的下载范围", discardPartial: true) }
        let bounds = pieces[1].split(separator: "/")
        let range = bounds.first?.split(separator: "-", omittingEmptySubsequences: false) ?? []
        guard bounds.count == 2, range.count == 2, let start = Int64(range[0]), let end = Int64(range[1]), let total = Int64(bounds[1]),
              start >= 0, end >= start, total > end else { throw DownloadFailure(message: "服务器返回了无效的下载范围", discardPartial: true) }
        self.start = start; self.end = end; self.total = total
    }
}

/// Keep one URLSession per manager so thousands of asset requests reuse TLS
/// connections. The router doesn't retain the transport, avoiding a delegate cycle.
final class DownloadTransport: @unchecked Sendable {
    let session: URLSession
    private let router: DownloadDelegateRouter
    init(configuration: URLSessionConfiguration) {
        router = DownloadDelegateRouter()
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: router, delegateQueue: queue)
    }
    deinit { session.invalidateAndCancel() }
    func makeTask(request: URLRequest, stream: DownloadStream) -> URLSessionDataTask {
        let task = session.dataTask(with: request)
        router.register(stream, for: task.taskIdentifier)
        return task
    }
}
private final class DownloadDelegateRouter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var streams: [Int: DownloadStream] = [:]
    func register(_ stream: DownloadStream, for id: Int) { lock.withLock { streams[id] = stream } }
    private func stream(_ task: URLSessionTask) -> DownloadStream? { lock.withLock { streams[task.taskIdentifier] } }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let stream = stream(dataTask) else { completionHandler(.cancel); return }
        stream.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { stream(dataTask)?.urlSession(session, dataTask: dataTask, didReceive: data) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let stream = lock.withLock { streams.removeValue(forKey: task.taskIdentifier) }
        stream?.urlSession(session, task: task, didCompleteWithError: error)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let stream = stream(task) else { completionHandler(nil); return }
        stream.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
    }
}

/// Delegate callbacks run on a serial operation queue. Only cancellation crosses
/// that queue; its task reference and early-cancellation flag share a lock.
final class DownloadStream: @unchecked Sendable {
    let partial: URL
    let metadata: URL
    let identity: String
    let sourceURL: String
    let offset: Int64
    let expectedSize: Int64?
    let progress: @Sendable (DownloadTransferProgress) -> Void
    private let taskLock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var continuation: CheckedContinuation<Void, any Error>?
    private var handle: FileHandle?
    private var failure: (any Error)?
    private var received: Int64 = 0
    private var resumed: Int64 = 0
    private var total: Int64?
    private var expectedEnd: Int64?
    private var lastReport = Date.distantPast

    init(partial: URL, metadata: URL, identity: String, sourceURL: String, offset: Int64, expectedSize: Int64?, progress: @escaping @Sendable (DownloadTransferProgress) -> Void) {
        self.partial = partial; self.metadata = metadata; self.identity = identity; self.sourceURL = sourceURL; self.offset = offset; self.expectedSize = expectedSize; self.progress = progress
    }
    func run(request: URLRequest, transport: DownloadTransport) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = transport.makeTask(request: request, stream: self)
                taskLock.lock(); self.task = task; let wasCancelled = cancelled; taskLock.unlock()
                task.resume()
                if wasCancelled { task.cancel() }
            }
        } onCancel: { self.cancel() }
    }
    private func cancel() {
        taskLock.lock(); cancelled = true; let task = task; taskLock.unlock()
        task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { failure = DownloadFailure(message: "下载服务重定向到了非 HTTPS 地址"); completionHandler(nil); return }
        var redirected = request
        for field in ["Range", "If-Range", "Accept-Encoding"] { redirected.setValue(task.originalRequest?.value(forHTTPHeaderField: field), forHTTPHeaderField: field) }
        completionHandler(redirected)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse else { throw DownloadFailure(message: "下载服务响应无效") }
            guard http.statusCode == 200 || http.statusCode == 206 else {
                throw DownloadFailure(message: "下载服务返回 HTTP \(http.statusCode)", discardPartial: http.statusCode == 416)
            }
            let encoding = http.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
            guard encoding == nil || encoding == "identity" else { throw DownloadFailure(message: "下载服务未提供可校验的原始文件", discardPartial: true) }
            if http.statusCode == 206 {
                let range = try HTTPContentRange(http.value(forHTTPHeaderField: "Content-Range") ?? "")
                guard range.start == offset, expectedSize == nil || expectedSize == range.total else { throw DownloadFailure(message: "服务器续传范围与本地文件不一致", discardPartial: true) }
                resumed = offset; received = offset; total = range.total; expectedEnd = range.end + 1
            } else {
                received = 0; resumed = 0
                total = expectedSize ?? (http.expectedContentLength >= 0 ? http.expectedContentLength : nil)
                expectedEnd = http.expectedContentLength >= 0 ? http.expectedContentLength : expectedSize
                if let expectedSize, let expectedEnd, expectedSize != expectedEnd { throw DownloadFailure(message: "服务器文件大小与清单不一致", discardPartial: true) }
            }
            if !FileManager.default.fileExists(atPath: partial.path) {
                guard FileManager.default.createFile(atPath: partial.path, contents: nil) else { throw DownloadFailure(message: "无法保存下载文件") }
            }
            let file = try FileHandle(forWritingTo: partial)
            handle = file
            if resumed == 0 { try file.truncate(atOffset: 0) }
            let length = try file.seekToEnd()
            guard length == UInt64(received) else { throw DownloadFailure(message: "本地续传文件在下载期间发生变化", discardPartial: true) }
            let state = DownloadResumeState(identity: identity, etag: http.value(forHTTPHeaderField: "ETag"), lastModified: http.value(forHTTPHeaderField: "Last-Modified"), sourceURL: sourceURL)
            try JSONEncoder().encode(state).write(to: metadata, options: .atomic)
            report(force: true)
            completionHandler(.allow)
        } catch { failure = error; completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil else { return }
        do {
            if let total, Int64(data.count) > total - received { throw DownloadFailure(message: "下载数据超过清单大小", discardPartial: true) }
            guard let handle else { throw DownloadFailure(message: "下载数据缺少有效响应", discardPartial: true) }
            try handle.write(contentsOf: data); received += Int64(data.count); report()
        } catch { failure = error; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        do { try handle?.synchronize(); try handle?.close() } catch { if failure == nil { failure = error } }
        handle = nil; report(force: true)
        let completion = continuation; continuation = nil
        taskLock.lock(); self.task = nil; taskLock.unlock()
        if let failure { completion?.resume(throwing: failure) }
        else if let error { completion?.resume(throwing: error) }
        else if let expectedEnd, received != expectedEnd { completion?.resume(throwing: DownloadFailure(message: "下载提前结束，可以继续重试")) }
        else { completion?.resume() }
    }
    private func report(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) >= 0.15 else { return }
        lastReport = now; progress(DownloadTransferProgress(receivedBytes: received, totalBytes: total, resumedBytes: resumed))
    }
}
