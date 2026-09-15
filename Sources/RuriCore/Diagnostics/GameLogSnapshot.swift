import Foundation
import Darwin
import RuriLocalization

/// An explicitly requested, private, immutable export snapshot. Large files
/// remain on disk; the GUI owns only a bounded preview. Never retain raw copies
/// after redaction or reopen a live source during export.
final class GameLogSnapshot: @unchecked Sendable {
    let directory: URL
    let file: URL
    let byteCount: Int
    let preview: String
    let changedByRedaction: Bool
    let previewTruncated: Bool

    private init(directory: URL, file: URL, byteCount: Int, preview: String, changed: Bool, previewTruncated: Bool) {
        self.directory = directory; self.file = file; self.byteCount = byteCount
        self.preview = preview; changedByRedaction = changed; self.previewTruncated = previewTruncated
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    static func capture(_ source: GameLogFile, redactor: GameShareRedactor) throws -> GameLogSnapshot {
        let directory = try workspace(), raw = directory.appendingPathComponent("source"), target = directory.appendingPathComponent("redacted.log")
        var success = false
        defer { try? FileManager.default.removeItem(at: raw); if !success { try? FileManager.default.removeItem(at: directory) } }
        let input = try source.openVerified(); defer { try? input.close() }
        // Clone from the verified descriptor, never resolve the source path a
        // second time. Other volumes fall back to a checked streaming copy.
        if fclonefileat(input.fileDescriptor, AT_FDCWD, raw.path, UInt32(CLONE_NOOWNERCOPY)) != 0 {
            let output = try create(raw); defer { try? output.close() }
            try copy(input, to: output, count: source.reference.size)
            var after = stat()
            guard fstat(input.fileDescriptor, &after) == 0, source.reference.matches(after, growing: source.growing) else { throw RuriError.message(Messages.CoreGameSession.logChangedDuringExport) }
        }
        var sourceAfter = stat()
        guard fstat(input.fileDescriptor, &sourceAfter) == 0, source.reference.matches(sourceAfter, growing: source.growing) else { throw RuriError.message(Messages.CoreGameSession.logChangedDuringExport) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: raw.path)
        let stable = try FileHandle(forReadingFrom: raw); defer { try? stable.close() }
        let length = try stable.seekToEnd(); try stable.seek(toOffset: 0)
        guard length >= UInt64(source.reference.size), source.growing || length == UInt64(source.reference.size) else { throw RuriError.message(Messages.CoreGameSession.logChangedDuringExport) }
        let result = try redact(stable, count: length, to: target, redactor: redactor)
        success = true
        return .init(directory: directory, file: target, byteCount: result.0, preview: result.1, changed: result.2, previewTruncated: result.3)
    }
    func redacting(_ redactor: GameShareRedactor) throws -> GameLogSnapshot {
        let directory = try Self.workspace(), target = directory.appendingPathComponent("redacted.log")
        var success = false; defer { if !success { try? FileManager.default.removeItem(at: directory) } }
        let input = try open(); defer { try? input.close() }
        let result = try Self.redact(input, count: UInt64(byteCount), to: target, redactor: redactor)
        success = true
        return .init(directory: directory, file: target, byteCount: result.0, preview: result.1, changed: changedByRedaction || result.2, previewTruncated: result.3)
    }
    func open() throws -> FileHandle {
        let fd = Darwin.open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(.ENOENT) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size == byteCount else { try? handle.close(); throw POSIXError(.EIO) }
        return handle
    }
    func export(to destination: URL) throws {
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".ruri-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let input = try open(); defer { try? input.close() }
        let output = try Self.create(staging); defer { try? output.close() }
        try Self.copy(input, to: output, count: Int64(byteCount))
        try output.synchronize(); try output.close()
        try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw POSIXError(.EIO) }
    }
    private static func workspace() throws -> URL {
        var template = Array(FileManager.default.temporaryDirectory.appendingPathComponent("ruri-export-XXXXXX").path.utf8CString)
        guard let path = mkdtemp(&template) else { throw POSIXError(.EIO) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
    private static func create(_ url: URL) throws -> FileHandle {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    private static func copy(_ input: FileHandle, to output: FileHandle, count: Int64) throws {
        var remaining = count
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try input.read(upToCount: Int(min(65_536, remaining))) ?? Data()
            guard !data.isEmpty else { throw RuriError.message(Messages.CoreGameSession.logChangedDuringExport) }
            try output.write(contentsOf: data); remaining -= Int64(data.count)
        }
    }
    private static func firstUnescaped(_ quote: UInt8, in data: Data) -> Data.Index? {
        var escaped = false
        for index in data.indices {
            let byte = data[index]
            if escaped { escaped = false }
            else if byte == 92 { escaped = true }
            else if byte == quote { return index }
        }
        return nil
    }
    private static func openCredentialQuote(_ text: String) -> UInt8? {
        let line = text.trimmingCharacters(in: .newlines)
        let range = NSRange(line.startIndex..., in: line)
        for (quote, expression) in unfinishedCredentials where expression.firstMatch(in: line, range: range) != nil { return quote }
        return nil
    }
    private static let unfinishedCredentials: [(UInt8, NSRegularExpression)] = {
        let prefix = #"(?i)(?:\b(?:access_token|refresh_token|id_token|client_secret|api[_-]?key|accessToken|refreshToken|sessionToken|token)\b["']?\s*[:=]\s*|--(?:accessToken|session|token|apiKey|refreshToken|idToken|clientSecret)(?:=|\s+))"#
        return [(34, #""(?:[^"\\\r\n]|\\.)*$"#), (39, #"'(?:[^'\\\r\n]|\\.)*$"#)].map { ($0.0, try! NSRegularExpression(pattern: prefix + $0.1)) }
    }()
    private static func redact(_ input: FileHandle, count: UInt64, to target: URL, redactor: GameShareRedactor) throws -> (Int, String, Bool, Bool) {
        let output = try create(target); defer { try? output.close() }
        var remaining = count, pending = Data(), first = Data(), buffered = Data()
        var last = GameOutputTail(capacity: 65_536)
        var written = 0, changed = false
        var sensitiveQuote: UInt8?
        func emit(_ line: Data) throws {
            try autoreleasepool {
                var text = String(decoding: line, as: UTF8.self)
                if let quote = sensitiveQuote {
                    if let index = firstUnescaped(quote, in: line) {
                        text = "<redacted>" + String(decoding: line[line.index(after: index)...], as: UTF8.self); sensitiveQuote = nil
                    } else { text = "<redacted>" + (line.last == 10 ? "\n" : "") }
                }
                // A quoted credential can span lines; don't expose its
                // continuation merely because this is a streaming reader.
                sensitiveQuote = sensitiveQuote ?? openCredentialQuote(text)
                let masked = redactor.redact(text), data = Data(masked.utf8)
                changed = changed || data != line
                buffered.append(data); written += data.count
                if buffered.count >= 65_536 { try output.write(contentsOf: buffered); buffered.removeAll(keepingCapacity: true) }
                if first.count < 65_536 { first.append(data.prefix(65_536 - first.count)) }
                last.append(data)
            }
        }
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try input.read(upToCount: Int(min(65_536, remaining))) ?? Data()
            guard !data.isEmpty else { throw POSIXError(.EIO) }
            remaining -= UInt64(data.count); pending.append(data)
            while let newline = pending.firstIndex(of: 10) {
                let end = pending.index(after: newline)
                guard pending.distance(from: pending.startIndex, to: end) <= 1_048_576 else { throw RuriError.message(Messages.SessionUI.unsafeLongLine) }
                try emit(Data(pending[..<end])); pending.removeSubrange(..<end)
            }
            // Never silently truncate a supposedly complete export. Extremely
            // long lines need a different privacy policy and are reported.
            guard pending.count <= 1_048_576 else { throw RuriError.message(Messages.SessionUI.unsafeLongLine) }
        }
        if !pending.isEmpty { try emit(pending) }
        if !buffered.isEmpty { try output.write(contentsOf: buffered) }
        try output.close()
        let partial = written > first.count
        var preview = String(decoding: first, as: UTF8.self)
        if partial {
            if let newline = preview.lastIndex(of: "\n") { preview = String(preview[...newline]) }
            let tail = String(decoding: last.snapshot(final: true), as: UTF8.self)
            preview += "\n" + Messages.SessionUI.fullFilePreview.localized + "\n" + tail
        }
        return (written, preview, changed, partial)
    }
}
