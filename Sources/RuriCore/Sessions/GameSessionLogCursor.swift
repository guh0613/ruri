import Foundation
import RuriLocalization

public struct GameLogPreview: Sendable {
    public let text: String
    public let origin: String?
    public let isProcessOutput: Bool
    public let needsLiveOutput: Bool
}

/// Only a visible console owns a cursor. Read appended bytes, skip to the tail
/// after a burst, and reopen on rotation. Native files are never rewritten.
public actor GameSessionLogCursor {
    private let paths: LauncherPaths
    private let session: GameSession
    private let source: GameSessionStore.LogSource
    private var handle: FileHandle?
    private var identity: String?
    private var observed: GameLogReference?
    private var offset: Int64 = 0
    private var tail = GameOutputTail(capacity: 1_048_576)
    public private(set) var lines: [String] = []
    public private(set) var updates: [String] = []
    public private(set) var preview = GameLogPreview(text: "", origin: nil, isProcessOutput: false, needsLiveOutput: false)

    public init(paths: LauncherPaths, session: GameSession, source: GameSessionStore.LogSource = .launcher) throws {
        self.paths = paths; self.session = session; self.source = source
    }
    deinit { try? handle?.close() }
    @discardableResult public func refresh(final: Bool = false) throws -> Bool {
        if source == .launcher {
            let current = (try? GameSessionStore.load(paths: paths, instanceID: session.instanceID, sessionID: session.id)) ?? session
            let text = try GameSessionStore.logTail(paths: paths, session: current, byteLimit: 262_144, source: .launcher)
            return replace(text, origin: Messages.SessionRuntime.launcherEvents.localized)
        }
        guard let file = try GameSessionStore.selectedFile(paths: paths, session: session, source: source) else {
            try? handle?.close(); handle = nil; identity = nil; observed = nil
            let live = (source == .console || source == .combined || source == .fallback) && !session.state.isFinished && session.monitorIdentity?.isAlive == true
            return replace("", origin: nil, process: live, live: live)
        }
        let key = "\(file.reference.device):\(file.reference.inode)"
        if key != identity || file.reference.size < offset || (file.reference.size == offset && observed != file.reference) {
            try? handle?.close(); handle = try file.openVerified(); identity = key
            offset = max(0, file.reference.size - 1_048_576)
            tail = GameOutputTail(capacity: 1_048_576, truncated: offset > 0)
            try handle?.seek(toOffset: UInt64(offset))
        }
        guard let handle else { return false }
        guard observed != file.reference else { return false }
        if file.reference.size - offset > 1_048_576 {
            offset = file.reference.size - 1_048_576
            tail = GameOutputTail(capacity: 1_048_576, truncated: true)
            try handle.seek(toOffset: UInt64(offset))
        }
        let data = try handle.read(upToCount: Int(min(1_048_576, max(0, file.reference.size - offset)))) ?? Data()
        offset += Int64(data.count); tail.append(data); observed = file.reference
        let text = GameLogRedactor().redact(String(decoding: tail.snapshot(final: true), as: UTF8.self))
        let process = file.reference.relativePath == "console.log" || file.reference.relativePath == "console-tail.log"
        return replace(text, origin: file.gameRelativePath ?? file.title, process: process)
    }
    private func replace(_ text: String, origin: String?, process: Bool = false, live: Bool = false) -> Bool {
        let changed = preview.text != text || preview.origin != origin || preview.needsLiveOutput != live
        if changed {
            let next = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(5000).map(String.init)
            updates = next; lines = next
            preview = .init(text: next.joined(separator: "\n"), origin: origin, isProcessOutput: process, needsLiveOutput: live)
        }
        return changed
    }
}
