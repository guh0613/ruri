import Darwin
import Foundation

/// Column metrics for terminal text. East Asian wide characters and emoji take
/// two columns; combining marks, joiners and ANSI styles take none.
enum TerminalText {
    static func width(_ text: String) -> Int {
        var total = 0, escape = false
        for character in text {
            if escape {
                // CSI sequences end with a final byte in @…~.
                if let scalar = character.unicodeScalars.first, (0x40...0x7E).contains(scalar.value), scalar != "[" { escape = false }
                continue
            }
            if character == "\u{1B}" { escape = true; continue }
            total += width(of: character)
        }
        return total
    }

    static func width(of character: Character) -> Int {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return 0 }
        if first.properties.generalCategory == .control { return 0 }
        if scalars.contains(where: { $0.properties.isEmojiPresentation }) || (first.properties.isEmoji && scalars.contains("\u{FE0F}")) { return 2 }
        if [.nonspacingMark, .enclosingMark, .format].contains(first.properties.generalCategory) { return 0 }
        return isWide(first.value) ? 2 : 1
    }

    private static func isWide(_ value: UInt32) -> Bool {
        switch value {
        case 0x1100...0x115F, 0x231A...0x231B, 0x2329...0x232A, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x2FFFD, 0x30000...0x3FFFD: true
        default: false
        }
    }

    static func pad(_ text: String, to columns: Int) -> String {
        text + String(repeating: " ", count: max(0, columns - width(text)))
    }

    /// Shortens text that is safe to abbreviate, such as a title.
    static func truncate(_ text: String, to columns: Int) -> String {
        guard width(text) > columns else { return text }
        guard columns > 1 else { return columns == 1 ? "…" : "" }
        var result = "", used = 0
        for character in text {
            let next = width(of: character)
            if used + next > columns - 1 { break }
            result.append(character); used += next
        }
        return result + "…"
    }

    /// Wraps at spaces, and between wide characters, which need no spaces.
    /// A word longer than the line stays whole, so paths and IDs remain copyable.
    static func wrap(_ text: String, width columns: Int) -> [String] {
        guard columns > 0 else { return [text] }
        var lines: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var line = "", lineWidth = 0
            for token in tokens(paragraph) {
                let tokenWidth = width(token)
                if token == " " {
                    if lineWidth > 0 && lineWidth < columns { line += " "; lineWidth += 1 }
                    continue
                }
                if lineWidth > 0 && lineWidth + tokenWidth > columns {
                    lines.append(line.trailingSpacesRemoved); line = ""; lineWidth = 0
                }
                line += token; lineWidth += tokenWidth
            }
            lines.append(line.trailingSpacesRemoved)
        }
        return lines
    }

    // Full-width comma, period, enumeration comma, semicolon, colon, exclamation
    // and question marks, and closing parentheses, brackets and quotation mark.
    private static let closingPunctuation = Set("\u{FF0C}\u{3002}\u{3001}\u{FF1B}\u{FF1A}\u{FF01}\u{FF1F}\u{FF09}\u{300D}\u{300F}\u{300B}\u{201D}")

    private static func tokens(_ text: String) -> [String] {
        var result: [String] = [], word = ""
        for character in text {
            if character == " " {
                if !word.isEmpty { result.append(word); word = "" }
                result.append(" ")
            } else if closingPunctuation.contains(character) {
                // Closing punctuation never starts a line.
                if !word.isEmpty { word.append(character) }
                else if let last = result.last, last != " " { result[result.count - 1] = last + String(character) }
                else { word.append(character) }
            } else if width(of: character) == 2 {
                if !word.isEmpty { result.append(word); word = "" }
                result.append(String(character))
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { result.append(word) }
        return result
    }

    /// Joins sentences, without a space after full-width punctuation.
    static func sentences(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.reduce("") { result, part in
            result.isEmpty ? part : result + (result.last.map { width(of: $0) == 2 } == true ? "" : " ") + part
        }
    }

    /// Packs items that must not be split, such as `--output <format>`, into lines.
    static func flow(_ items: [String], separator: String = "  ", width columns: Int) -> [String] {
        var lines: [String] = [], line = ""
        for item in items {
            if !line.isEmpty, width(line + separator + item) > columns { lines.append(line); line = "" }
            line += (line.isEmpty ? "" : separator) + item
        }
        return line.isEmpty ? lines : lines + [line]
    }

    /// Lays out `label  text` pairs, wrapping text in its own column. A label
    /// wider than the column puts its text on the next line.
    static func columns(_ rows: [(String, String)], indent: Int = 2, gap: Int = 2, maximumLabel: Int = 28, width total: Int) -> [String] {
        let labelWidth = rows.map { width($0.0) }.filter { $0 <= maximumLabel }.max() ?? 0
        let textColumn = indent + labelWidth + gap
        let margin = String(repeating: " ", count: indent), hanging = String(repeating: " ", count: textColumn)
        var lines: [String] = []
        // Too narrow for two columns: each text goes under its label.
        if total - textColumn < 24 {
            for (label, text) in rows {
                lines.append(margin + label)
                lines += text.isEmpty ? [] : wrap(text, width: max(10, total - indent - 4)).map { margin + "    " + $0 }
            }
            return lines
        }
        for (label, text) in rows {
            let wrapped = text.isEmpty ? [] : wrap(text, width: max(20, total - textColumn))
            if width(label) > labelWidth {
                lines.append(margin + label)
                lines += wrapped.map { hanging + $0 }
            } else if let first = wrapped.first {
                lines.append(margin + pad(label, to: labelWidth) + String(repeating: " ", count: gap) + first)
                lines += wrapped.dropFirst().map { hanging + $0 }
            } else {
                lines.append(margin + label)
            }
        }
        return lines
    }
}

private extension String {
    var trailingSpacesRemoved: String {
        var result = self
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}

/// Where text output goes, as measured at startup. Output written to a custom
/// sink is treated as a pipe: 80 columns, no TTY features.
struct TerminalProfile: Sendable {
    struct Stream: Sendable {
        var isTerminal: Bool
        var width: Int
    }
    var output: Stream
    var error: Stream
    var environment: [String: String]

    static let pipe = TerminalProfile(output: .init(isTerminal: false, width: 80), error: .init(isTerminal: false, width: 80), environment: [:])

    static func current() -> TerminalProfile {
        func stream(_ descriptor: Int32) -> Stream {
            guard isatty(descriptor) == 1 else { return .init(isTerminal: false, width: 80) }
            var size = winsize()
            let columns = ioctl(descriptor, TIOCGWINSZ, &size) == 0 && size.ws_col > 0 ? Int(size.ws_col) : 80
            return .init(isTerminal: true, width: columns)
        }
        return .init(output: stream(STDOUT_FILENO), error: stream(STDERR_FILENO), environment: ProcessInfo.processInfo.environment)
    }

    /// An explicit mode wins, then NO_COLOR, then the stream and TERM.
    func colors(_ stream: Stream, mode: String?) -> Bool {
        switch mode {
        case "always": return true
        case "never": return false
        default:
            if let value = environment["NO_COLOR"], !value.isEmpty { return false }
            guard stream.isTerminal, let term = environment["TERM"], !term.isEmpty, term != "dumb" else { return false }
            return true
        }
    }
}
