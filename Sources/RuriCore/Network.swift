import Foundation
import CryptoKit

public struct HTTPClient: Sendable {
    public static let shared = HTTPClient()
    public let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        return try await data(for: request)
    }
    public func data(for input: URLRequest) async throws -> Data {
        var request = input
        request.setValue("Ruri/0.1 (macOS Minecraft launcher)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw RuriError.message("\(request.url?.host ?? "服务") 返回 HTTP \(status)。请检查网络后重试。")
        }
        return data
    }
    public func get<T: Decodable & Sendable>(_ type: T.Type, from url: URL) async throws -> T {
        try JSONDecoder().decode(type, from: await data(from: url))
    }
}

public struct DownloadItem: Sendable {
    public let url: URL?
    public let destination: URL
    public let sha1: String?
    public let sha512: String?
    public let size: Int64?
    public init(url: URL?, destination: URL, sha1: String? = nil, sha512: String? = nil, size: Int64? = nil) {
        self.url = url; self.destination = destination; self.sha1 = sha1; self.sha512 = sha512; self.size = size
    }
    public init(_ artifact: Artifact, to destination: URL) { self.init(url: artifact.url, destination: destination, sha1: artifact.sha1, size: artifact.size) }
}

public actor DownloadManager {
    private let transport: DownloadTransport
    private let retryDelay: Duration
    private var inFlight: [String: (identity: String, task: Task<Void, any Error>)] = [:]
    public init(configuration: URLSessionConfiguration = .default, retryDelay: Duration = .seconds(1)) {
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 1800
        self.transport = DownloadTransport(configuration: config); self.retryDelay = retryDelay
    }
    public func download(_ items: [DownloadItem], concurrency: Int = 8, progress: @Sendable @escaping (Int, Int) async -> Void = { _, _ in }) async throws {
        // A shared artifact appears many times in asset indexes. Do not race writers.
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.destination.path).inserted }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var next = 0; var completed = 0
            let limit = min(max(concurrency, 1), 16)
            while next < min(limit, unique.count) {
                let item = unique[next]; group.addTask { try await self.fetch(item) }; next += 1
            }
            while try await group.next() != nil {
                completed += 1; await progress(completed, unique.count)
                try Task.checkCancellation()
                if next < unique.count { let item = unique[next]; group.addTask { try await self.fetch(item) }; next += 1 }
            }
        }
    }
    public func fetch(_ item: DownloadItem, progress: @escaping @Sendable (DownloadTransferProgress) -> Void = { _ in }) async throws {
        try Task.checkCancellation()
        if Self.valid(item.destination, item: item) { return }
        guard let url = item.url else { throw RuriError.message("安装器生成的文件缺失或损坏：\(item.destination.lastPathComponent)。请修复此实例。") }
        guard url.scheme == "https" else { throw RuriError.message("下载仅接受 HTTPS：\(url.host ?? "未知来源")") }
        let identity = Self.identity(item)
        let key = item.destination.standardizedFileURL.path
        if let existing = inFlight[key] {
            guard existing.identity == identity else { throw RuriError.message("多个下载要求写入同一文件：\(item.destination.lastPathComponent)") }
            try await existing.task.value; try Task.checkCancellation(); return
        }
        let task = Task { try await self.performFetch(item, identity: identity, progress: progress) }
        inFlight[key] = (identity, task)
        defer { inFlight[key] = nil }
        try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    static func identity(_ item: DownloadItem) -> String {
        let values = [item.url?.absoluteString ?? "", item.destination.standardizedFileURL.path, item.sha1 ?? "", item.sha512 ?? "", item.size.map(String.init) ?? ""]
        return SHA256.hash(data: Data(values.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func partialFiles(_ item: DownloadItem) -> (data: URL, metadata: URL) {
        let root = item.destination.deletingLastPathComponent().appendingPathComponent(".ruri-partials")
        let name = identity(item)
        return (root.appendingPathComponent(name + ".part"), root.appendingPathComponent(name + ".json"))
    }
    private func performFetch(_ item: DownloadItem, identity: String, progress: @escaping @Sendable (DownloadTransferProgress) -> Void) async throws {
        guard let url = item.url else { throw RuriError.message("文件缺少下载地址") }
        try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let files = Self.partialFiles(item)
        try FileManager.default.createDirectory(at: files.data.deletingLastPathComponent(), withIntermediateDirectories: true)
        func discard() { try? FileManager.default.removeItem(at: files.data); try? FileManager.default.removeItem(at: files.metadata) }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            do {
                if Self.valid(files.data, item: item), item.sha1 != nil || item.sha512 != nil {
                    guard rename(files.data.path, item.destination.path) == 0 else { throw RuriError.message("无法保存已校验的下载文件") }
                    try? FileManager.default.removeItem(at: files.metadata); return
                }
                let state = (try? Data(contentsOf: files.metadata)).flatMap { try? JSONDecoder().decode(DownloadResumeState.self, from: $0) }
                let info = try? FileManager.default.attributesOfItem(atPath: files.data.path)
                var offset = (info?[.size] as? NSNumber)?.int64Value ?? 0
                if state?.identity != identity || info?[.type] as? FileAttributeType != .typeRegular || (state?.validator == nil && item.sha1 == nil && item.sha512 == nil) || (item.size.map { offset >= $0 } ?? false) {
                    discard(); offset = 0
                }
                var request = URLRequest(url: url)
                request.setValue("Ruri/0.1 (macOS Minecraft launcher)", forHTTPHeaderField: "User-Agent")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                if offset > 0 {
                    request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
                    if let validator = state?.validator { request.setValue(validator, forHTTPHeaderField: "If-Range") }
                }
                let stream = DownloadStream(partial: files.data, metadata: files.metadata, identity: identity, offset: offset, expectedSize: item.size, progress: progress)
                try await stream.run(request: request, transport: transport)
                try Task.checkCancellation()
                guard Self.valid(files.data, item: item) else { throw DownloadFailure(message: "文件校验失败：\(item.destination.lastPathComponent)", discardPartial: true) }
                guard rename(files.data.path, item.destination.path) == 0 else { throw RuriError.message("无法保存下载：\(item.destination.lastPathComponent)") }
                try? FileManager.default.removeItem(at: files.metadata)
                return
            } catch {
                if (error as? DownloadFailure)?.discardPartial == true { discard() }
                if Task.isCancelled { throw CancellationError() }
                if attempt == 2 { throw error }
                try await Task.sleep(for: retryDelay * (attempt + 1))
            }
        }
    }
    public nonisolated static func valid(_ file: URL, item: DownloadItem) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path), attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value > 0 || item.size == 0 else { return false }
        if let expected = item.size, size.int64Value != expected { return false }
        guard item.sha1 != nil || item.sha512 != nil else { return true }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        var sha1 = Insecure.SHA1(); var sha512 = SHA512()
        do {
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                if item.sha1 != nil { sha1.update(data: chunk) }
                if item.sha512 != nil { sha512.update(data: chunk) }
            }
        } catch { return false }
        if let hash = item.sha1, sha1.finalize().map({ String(format: "%02x", $0) }).joined() != hash.lowercased() { return false }
        if let hash = item.sha512, sha512.finalize().map({ String(format: "%02x", $0) }).joined() != hash.lowercased() { return false }
        return true
    }
}
