import Foundation
import Darwin
import RuriLocalization

/// Bounded analysis reads are separate from complete, explicit file export.
enum GameNativeLogCollector {
    struct Snapshot {
        var documents: [GameDiagnosticDocument] = []
        var limitations: [String] = []
        var names: Set<String> = []
    }
    static func collect(paths: LauncherPaths, session: GameSession, budget: inout Int) throws -> Snapshot {
        var result = Snapshot()
        for source in try GameLogSources.native(paths: paths, session: session) {
            do {
                let documents = try read(source, budget: &budget, perFileLimit: 8 * 1_048_576)
                result.documents += documents
                if !documents.isEmpty { result.names.insert(source.title) }
                if documents.contains(where: \.truncated) { result.limitations.append(Messages.CoreGameDiagnosis.boundedTail(source.title).localized) }
            } catch is CancellationError { throw CancellationError() }
            catch { result.limitations.append(Messages.NativeGameLogs.unreadable(source.title).localized) }
        }
        if result.documents.isEmpty { result.limitations.append(Messages.NativeGameLogs.noMatchingLogs.localized) }
        return result
    }
    static func read(_ source: GameLogFile, budget: inout Int, perFileLimit: Int = 2 * 1_048_576) throws -> [GameDiagnosticDocument] {
        try Task.checkCancellation()
        let limit = min(budget, perFileLimit)
        guard limit > 0 else { return [] }
        let handle = try source.openVerified(); defer { try? handle.close() }
        let length = UInt64(source.reference.size), partial = length > limit
        let headCount = partial ? limit / 2 : Int(length)
        let head = try handle.read(upToCount: headCount) ?? Data()
        func document(_ input: Data, tail: Bool) -> GameDiagnosticDocument {
            var data = input
            if partial {
                if tail {
                    if let newline = data.firstIndex(of: 10) { data.removeSubrange(...newline) } else { data.removeAll() }
                } else if let newline = data.lastIndex(of: 10) { data.removeSubrange(data.index(after: newline)...) }
                else { data.removeAll() }
            }
            return .init(id: source.id + (tail ? "#tail" : ""), relativePath: source.gameRelativePath == nil ? source.reference.relativePath : nil,
                         title: source.title, kind: source.kind, text: GameLogRedactor().redact(String(decoding: data, as: UTF8.self)),
                         isTail: tail, truncated: partial || source.truncated, gameRelativePath: source.gameRelativePath)
        }
        var documents = [document(head, tail: false)], consumed = head.count
        if partial {
            let count = limit - headCount
            try handle.seek(toOffset: length - UInt64(count))
            let tail = try handle.read(upToCount: count) ?? Data()
            consumed += tail.count; documents.append(document(tail, tail: true))
        }
        var after = stat()
        guard fstat(handle.fileDescriptor, &after) == 0, source.reference.matches(after, growing: source.growing) else { throw RuriError.message(Messages.CoreGameSession.logChangedDuringExport) }
        budget -= consumed
        return documents
    }
}
