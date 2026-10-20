import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

/// The command path and global settings of an invocation, found before
/// ArgumentParser runs so help, errors and execution locate the same command.
struct CommandLineInvocation {
    /// Command names first, then the leaf's own arguments, then global options
    /// that appeared before or between command names. `--` keeps everything
    /// after it literal.
    var arguments: [String]
    var path: [String]
    /// The arguments after the command path, global options included.
    var rest: [String]
    var helpRequested = false
    var format: CommandOutput.Format = .text
    var quiet = false
    var language: String?

    init(_ input: [String]) {
        var path: [String] = [], moved: [String] = [], index = 0
        while index < input.count {
            let argument = input[index], name = Self.optionName(argument)
            if argument == "--" { break }
            if CommonOptions.flags.contains(argument) { moved.append(argument); index += 1; continue }
            if CommonOptions.valued.contains(name) {
                moved.append(argument); index += 1
                if !argument.contains("="), index < input.count, !input[index].hasPrefix("--") { moved.append(input[index]); index += 1 }
                continue
            }
            guard CommandHelp.spec(path) == nil, CommandHelp.commandType(path + [argument]) != nil else { break }
            path.append(argument); index += 1
        }
        var rest = Array(input[index...])
        if let terminator = rest.firstIndex(of: "--") { rest.insert(contentsOf: moved, at: terminator) } else { rest += moved }
        self.path = path
        self.rest = rest
        arguments = path + rest
        scanGlobals()
    }

    var isLeaf: Bool { CommandHelp.spec(path) != nil }

    /// Whether nothing but global options follows the command path.
    var hasOnlyGlobals: Bool {
        var index = 0
        while index < rest.count {
            let argument = rest[index], name = Self.optionName(argument)
            index += 1
            if CommonOptions.flags.contains(argument) { continue }
            guard CommonOptions.valued.contains(name) else { return false }
            if !argument.contains("="), index < rest.count, !rest[index].hasPrefix("--") { index += 1 }
        }
        return true
    }

    /// Global settings read before parsing, for help and parse errors. Values
    /// of options and anything after `--` are never read as settings.
    private mutating func scanGlobals() {
        var index = 0
        let options = Array(rest.prefix { $0 != "--" })
        while index < options.count {
            let argument = options[index], name = Self.optionName(argument)
            index += 1
            if ["--help", "-h", "--help-hidden"].contains(argument) { helpRequested = true }
            if argument == "--json" { format = .json }
            if argument == "--quiet" { quiet = true }
            guard CommonOptions.valued.contains(name) else { continue }
            var value: String?
            if let separator = argument.firstIndex(of: "=") { value = String(argument[argument.index(after: separator)...]) }
            else if index < options.count, !options[index].hasPrefix("--") { value = options[index]; index += 1 }
            if name == "--language" { language = value }
            if name == "--output", format != .json, let value, let selected = CommandOutput.Format(rawValue: value) { format = selected }
        }
    }

    static func optionName(_ argument: String) -> String {
        argument.hasPrefix("--") ? String(argument.split(separator: "=", maxSplits: 1).first ?? "") : argument
    }

    /// Unknown words, options and missing values, reported against the command
    /// the user was typing, with a suggestion when one is close.
    func problem() -> OperationFailure? {
        let words = rest.prefix { $0 != "--" }
        guard let spec = CommandHelp.spec(path) else {
            guard let word = words.first(where: { !CommonOptions.flags.contains($0) && !CommonOptions.valued.contains(Self.optionName($0)) }) else { return nil }
            let names = CommandHelp.subcommands(path).compactMap { $0.configuration.commandName }
            if word.hasPrefix("-") {
                // The root's own flags belong to ArgumentParser.
                if path.isEmpty && ["--version", "--generate-completion-script", "--experimental-dump-help"].contains(Self.optionName(word)) { return nil }
                return Self.failure(Messages.CLIExperience.unknownOption(word).localized, suggestion: Self.suggestion(for: word, in: Array(CommonOptions.flags) + Array(CommonOptions.valued)), path: path)
            }
            let message = path.isEmpty ? Messages.CLIExperience.unknownCommand(word).localized
                : Messages.CLIExperience.unknownSubcommand(word, (["ruri"] + path).joined(separator: " ")).localized
            return Self.failure(message, suggestion: Self.suggestion(for: word, in: names + (path.isEmpty ? ["help"] : [])), path: path)
        }
        let valued = Set(spec.options.filter { $0.type != "bool" }.map { "--" + $0.name }).union(CommonOptions.valued)
        let flags = Set(spec.options.filter { $0.type == "bool" }.map { "--" + $0.name }).union(CommonOptions.flags)
        var index = 0, positional: [String] = []
        while index < rest.count {
            let argument = rest[index]; index += 1
            if argument == "--" { positional += rest[index...]; break }
            guard argument.hasPrefix("-"), argument != "-" else { positional.append(argument); continue }
            let name = Self.optionName(argument)
            if valued.contains(name) {
                if !argument.contains("=") {
                    guard index < rest.count, !rest[index].hasPrefix("--") else { return Self.failure(Messages.CLIExperience.missingValue(name).localized, path: path) }
                    index += 1
                }
            } else if !flags.contains(name) {
                let candidates = Array(valued) + Array(flags).filter { $0.hasPrefix("--") }
                return Self.failure(Messages.CLIExperience.unknownOption(name).localized, suggestion: Self.suggestion(for: name, in: candidates), path: path)
            }
        }
        if positional.count > spec.operands.count {
            return Self.failure(Messages.CLIExperience.unexpectedArgument(positional[spec.operands.count]).localized, path: path)
        }
        return nil
    }

    static func failure(_ message: String, suggestion: String? = nil, path: [String]) -> OperationFailure {
        let text = suggestion.map { Messages.CLIExperience.withSuggestion(message, $0).localized } ?? message
        return OperationFailure("INVALID_ARGUMENT", text, nextActions: [.init(["help"] + path)])
    }

    /// The closest candidate within a small edit distance, or a unique prefix match.
    static func suggestion(for word: String, in candidates: [String]) -> String? {
        let typed = word.lowercased()
        let prefixed = candidates.filter { $0.lowercased().hasPrefix(typed) }
        if typed.count >= 2, prefixed.count == 1 { return prefixed[0] }
        let scored = candidates.map { ($0, distance(typed, $0.lowercased())) }.filter { $0.1 <= max(1, min(2, typed.count / 3)) }
        guard let best = scored.min(by: { $0.1 < $1.1 }), scored.filter({ $0.1 == best.1 }).count == 1 else { return nil }
        return best.0
    }

    /// Optimal string alignment distance, so swapped letters count as one edit.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1) }
            }
        }
        return table[a.count][b.count]
    }
}
