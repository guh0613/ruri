import RuriLocalization
import Foundation

public struct FileTransfer: Identifiable, Sendable {
    public enum State: String, Codable, Sendable {
        case receiving, retrying, completed, failed, cancelled
        public var isActive: Bool { self == .receiving || self == .retrying }
        public var title: String { switch self { case .receiving: Messages.CoreDownloadActivity.titleText1.localized; case .retrying: Messages.CoreDownloadActivity.titleText2.localized; case .completed: Messages.CoreDownloadActivity.titleText3.localized; case .failed: Messages.CoreDownloadActivity.titleText4.localized; case .cancelled: Messages.CoreDownloadActivity.titleText5.localized } }
    }
    public let id: String
    public let filename: String
    public internal(set) var host: String
    public internal(set) var attempt: Int
    public internal(set) var state: State
    public internal(set) var receivedBytes: Int64
    public internal(set) var totalBytes: Int64?
    public internal(set) var resumedBytes: Int64
    public internal(set) var bytesPerSecond: Double
    public internal(set) var message: String?
    public internal(set) var updatedAt: Date
    var generation: UUID
}

extension DownloadManager {
    public func transfers() -> [FileTransfer] {
        transferRecords.values.sorted {
            $0.state.isActive != $1.state.isActive ? $0.state.isActive : $0.updatedAt > $1.updatedAt
        }.prefix(24).map { $0 }
    }
    func beginTransfer(_ item: DownloadItem, id: String, url: URL, attempt: Int, offset: Int64) -> UUID {
        if transferRecords.count >= 80 {
            let old = transferRecords.values.filter { !$0.state.isActive }.sorted { $0.updatedAt < $1.updatedAt }.prefix(20)
            for entry in old { transferRecords[entry.id] = nil }
        }
        let generation = UUID()
        transferRecords[id] = FileTransfer(id: id, filename: item.destination.lastPathComponent, host: url.host ?? "", attempt: attempt,
            state: .receiving, receivedBytes: offset, totalBytes: item.size, resumedBytes: offset, bytesPerSecond: 0, updatedAt: Date(), generation: generation)
        return generation
    }
    func updateTransfer(_ id: String, generation: UUID, progress: DownloadTransferProgress) {
        guard var entry = transferRecords[id], entry.generation == generation, entry.state == .receiving else { return }
        let now = Date(); let elapsed = now.timeIntervalSince(entry.updatedAt)
        if elapsed >= 0.04 { entry.bytesPerSecond = Double(max(0, progress.receivedBytes - entry.receivedBytes)) / elapsed }
        entry.receivedBytes = progress.receivedBytes; entry.totalBytes = progress.totalBytes; entry.resumedBytes = progress.resumedBytes; entry.updatedAt = now
        transferRecords[id] = entry
    }
    func retryTransfer(_ id: String, message: String) {
        guard var entry = transferRecords[id] else { return }
        entry.state = .retrying; entry.message = message; entry.bytesPerSecond = 0; entry.updatedAt = Date(); transferRecords[id] = entry
    }
    func finishTransfer(_ id: String, item: DownloadItem, error: (any Error)? = nil) {
        guard var entry = transferRecords[id] else { return }
        entry.state = error == nil ? .completed : error is CancellationError ? .cancelled : .failed
        if error == nil, let size = (try? FileManager.default.attributesOfItem(atPath: item.destination.path)[.size]) as? NSNumber {
            entry.receivedBytes = size.int64Value; entry.totalBytes = size.int64Value
        }
        entry.message = error?.localizedDescription; entry.bytesPerSecond = 0; entry.updatedAt = Date(); transferRecords[id] = entry
    }
}
