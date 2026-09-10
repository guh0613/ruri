import Foundation

/// Ordering for dependency versions found in Minecraft launch manifests.
/// Numeric segments are unbounded; punctuation and digit/text transitions
/// introduce subordinate segments, as in HMCL's dependency version ordering.
enum MinecraftDependencyVersion {
    static func compare(_ first: String, _ second: String) -> ComparisonResult {
        let result = compare(parse(first), parse(second))
        return result == 0 ? .orderedSame : result < 0 ? .orderedAscending : .orderedDescending
    }

    private indirect enum Part {
        case number(String), word(String), group([Part])
        var zero: Bool {
            switch self {
            case .number(let value): value.isEmpty
            case .word(let value): value.isEmpty
            case .group(let values): values.isEmpty
            }
        }
        var rank: Int { switch self { case .word: 0; case .group: 1; case .number: 2 } }
    }

    private static func parse(_ version: String) -> Part {
        var levels: [[Part]] = [[]], text = "", wasDigit: Bool?
        let separators = CharacterSet(charactersIn: "!\"#$%&'()*+,-/:;<=>?@[\\]^_`{|}~")
        func token(_ value: String) -> Part {
            if value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }) {
                return .number(String(value.drop(while: { $0 == "0" })))
            }
            return .word(value)
        }
        for character in version.unicodeScalars {
            if character == "." || separators.contains(character) {
                levels[levels.count - 1].append(token(text)); text = ""
                if character != "." { levels.append([]) }
            } else {
                let digit = (48...57).contains(character.value)
                if !text.isEmpty, let previous = wasDigit, previous != digit {
                    levels[levels.count - 1].append(token(text)); text = ""; levels.append([])
                }
                text.unicodeScalars.append(character); wasDigit = digit
            }
        }
        if !text.isEmpty { levels[levels.count - 1].append(token(text)) }
        while levels.count > 1 {
            let child = normalize(levels.removeLast())
            levels[levels.count - 1].append(.group(child))
        }
        return .group(normalize(levels[0]))
    }

    private static func normalize(_ input: [Part]) -> [Part] {
        var parts = input
        for index in parts.indices.reversed() {
            if parts[index].zero { parts.remove(at: index) }
            else if case .group = parts[index] { continue }
            else { break }
        }
        return parts
    }

    private static func compare(_ first: Part?, _ second: Part?) -> Int {
        guard let first else { return second == nil ? 0 : -compare(second, nil) }
        guard let second else {
            switch first {
            case .number(let number): return number.isEmpty ? 0 : 1
            case .word(let word):
                let label = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return ["alpha", "beta", "pre", "rc", "experimental"].contains(where: label.hasPrefix) ? -1 : 1
            case .group(let parts): return compare(parts.first, nil)
            }
        }
        switch (first, second) {
        case (.number(let a), .number(let b)):
            if a.count != b.count { return a.count < b.count ? -1 : 1 }
            return a.utf16.elementsEqual(b.utf16) ? 0 : a.utf16.lexicographicallyPrecedes(b.utf16) ? -1 : 1
        case (.word(let a), .word(let b)):
            return a.utf16.elementsEqual(b.utf16) ? 0 : a.utf16.lexicographicallyPrecedes(b.utf16) ? -1 : 1
        case (.group(let a), .group(let b)):
            for index in 0..<max(a.count, b.count) {
                let result = compare(index < a.count ? a[index] : nil, index < b.count ? b[index] : nil)
                if result != 0 { return result }
            }
            return 0
        default: return first.rank < second.rank ? -1 : 1
        }
    }
}
