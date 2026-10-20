import Foundation
import RuriCore
import RuriLocalization

/// ANSI styles, applied only when colors are on. Styled words always read
/// correctly without color.
struct TextStyle: Sendable {
    var colors = false
    func bold(_ text: String) -> String { paint(text, "1") }
    func dim(_ text: String) -> String { paint(text, "2") }
    func good(_ text: String) -> String { paint(text, "32") }
    func warning(_ text: String) -> String { paint(text, "33") }
    func bad(_ text: String) -> String { paint(text, "31") }
    private func paint(_ text: String, _ code: String) -> String { colors && !text.isEmpty ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text }
}

/// A list column. Columns hide from the highest priority down when the
/// terminal is narrow; priority 0 never hides.
struct ListColumn {
    let header: String
    var priority = 0
    /// Shown only with --details.
    var detailOnly = false
    let cell: (Value) -> String
}

/// The measured width, colors and detail level of one text output.
struct TextLayout: Sendable {
    var width = 80
    var style = TextStyle()
    var details = false

    /// Aligned `label  value` rows without empty values. Values wrap in their
    /// column; words that cannot break, such as paths, stay whole.
    func fields(_ rows: [(String, String)], indent: Int = 2) -> [String] {
        let rows = rows.filter { !$0.1.isEmpty }.map { ($0.0, Self.keepingPathsWhole($0.1)) }
        return TerminalText.columns(rows, indent: indent, maximumLabel: 20, width: width).map { $0.replacingOccurrences(of: "\u{A0}", with: " ") }
    }

    /// A path keeps its spaces on one line, so it can be copied whole, also
    /// when it is one part of a value such as `21 · /path` or `old → "/path"`.
    private static func keepingPathsWhole(_ value: String) -> String {
        for separator in [" → ", " · "] where value.contains(separator) {
            return value.components(separatedBy: separator).map(keepingPathsWhole).joined(separator: separator)
        }
        let path = value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("\"/")
        return path ? value.replacingOccurrences(of: " ", with: "\u{A0}") : value
    }

    /// A titled group of fields, or nothing when every value is empty.
    func section(_ title: String, _ rows: [(String, String)]) -> [String] {
        let rows = rows.filter { !$0.1.isEmpty }
        return rows.isEmpty ? [] : [style.bold(title)] + fields(rows)
    }

    func paragraph(_ text: String) -> [String] { TerminalText.wrap(text, width: width).map(Self.restoringSpaces) }

    /// A paragraph indented as a whole, wrapped to the space left.
    func paragraph(_ text: String, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        return text.components(separatedBy: "\n").flatMap { TerminalText.wrap($0, width: max(20, width - indent)) }.map { $0.isEmpty ? "" : pad + Self.restoringSpaces($0) }
    }

    /// Text, such as a path inside a sentence, that wrapping must not split.
    static func unbroken(_ text: String) -> String { text.replacingOccurrences(of: " ", with: "\u{A0}") }
    private static func restoringSpaces(_ line: String) -> String { line.replacingOccurrences(of: "\u{A0}", with: " ") }

    /// Items that each start with a bullet and wrap under their own text.
    func bullets(_ items: [String], indent: Int = 2) -> [String] {
        let pad = String(repeating: " ", count: indent)
        return items.flatMap { item in
            TerminalText.wrap(item, width: max(20, width - indent - 2)).enumerated().map { pad + ($0.offset == 0 ? "• " : "  ") + $0.element }
        }
    }

    /// A sentence wrapped to the width, each line styled on its own.
    func prose(_ text: String, _ paint: (String) -> String = { $0 }) -> [String] { paragraph(text).map(paint) }

    /// A table when the essential columns fit, otherwise one block per item.
    /// Reports whether columns were hidden to fit; --details hides none.
    func table(_ columns: [ListColumn], _ items: [Value]) -> (lines: [String], hidden: Bool) {
        let columns = columns.filter { details || !$0.detailOnly }
        let cells = items.map { item in columns.map { $0.cell(item) } }
        // A column that is empty for every item carries nothing.
        var visible = columns.indices.filter { index in columns[index].priority == 0 || cells.contains { !$0[index].isEmpty } }
        let widths = columns.indices.map { index in ([columns[index].header] + cells.map { $0[index] }).map(TerminalText.width).max() ?? 0 }
        func total(_ indices: [Int]) -> Int { indices.map { widths[$0] }.reduce(0, +) + 2 * max(0, indices.count - 1) }
        let available = visible
        while !details, total(visible) > width, let drop = visible.filter({ columns[$0].priority > 0 }).max(by: { (columns[$0].priority, $0) < (columns[$1].priority, $1) }) {
            visible.removeAll { $0 == drop }
        }
        guard total(visible) <= width else { return (vertical(columns, cells, shown: available), false) }
        func row(_ values: [String]) -> String {
            visible.enumerated().map { position, index in
                position == visible.count - 1 ? values[index] : TerminalText.pad(values[index], to: widths[index]) + "  "
            }.joined().trailingSpacesTrimmed
        }
        let header = style.bold(row(columns.map(\.header)))
        return ([header] + cells.map(row), visible.count < available.count)
    }

    /// One block per item: the first column as its title, the rest as fields.
    private func vertical(_ columns: [ListColumn], _ cells: [[String]], shown: [Int]) -> [String] {
        cells.enumerated().flatMap { offset, values -> [String] in
            let title = shown.first.map { values[$0] } ?? ""
            let rows = shown.dropFirst().map { (columns[$0].header, values[$0]) }
            return (offset == 0 ? [] : [""]) + [style.bold(title)] + fields(rows)
        }
    }
}

extension String {
    var trailingSpacesTrimmed: String {
        var result = self
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}

extension Value {
    /// The values of an array, or none.
    var elements: [Value] { if case .array(let values) = self { values } else { [] } }
    var strings: [String] { elements.compactMap(\.string) }
}

/// Readable sizes, durations and dates. Exact values remain in --details and JSON.
enum TextFormat {
    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))
    }

    static func bytes(_ value: Value) -> String { value.int.map { bytes(Int64($0)) } ?? "" }

    /// A file count with the size of those files.
    static func contents(files: Value, bytes size: Value) -> String {
        [files.int.map { Messages.CLIExperience.fileCount(Int64($0)).localized }, size.int.map { bytes(Int64($0)) }].compactMap { $0 }.joined(separator: " · ")
    }

    static func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute, .second] : [.second]
        formatter.calendar = calendar
        return formatter.string(from: max(0, seconds.rounded())) ?? "\(Int(seconds))s"
    }

    static func date(_ value: Value) -> String {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let text = value.string, let date = ISO8601DateFormatter().date(from: text) ?? fractional.date(from: text) else { return value.string ?? "" }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    static var locale: Locale { Locale(identifier: LocalizationContext.current.language) }
    private static var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.locale = locale; return calendar }
}
