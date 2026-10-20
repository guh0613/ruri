import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

/// Shell completion derived from parameter roles. Values from local state come
/// from the same indexes as target resolution, so every candidate resolves.
/// State is only read: nothing is created, migrated, repaired or fetched, and
/// anything unreadable completes nothing.
enum CommandCompletion {
    enum Slot: Sendable { case operand(Int), option(String) }

    static func kind(for slot: Slot, in spec: CommandSpec) -> CompletionKind? {
        guard let parameter = parameter(slot, in: spec), parameter.type != "bool" else { return nil }
        switch parameter.role {
        case .file, .newFile: return .file()
        case .folder: return .directory
        case .text: return parameter.values.isEmpty ? nil : .list(parameter.values)
        default:
            let path = spec.path
            return .custom { (words: [String], index: Int, prefix: String) -> [String] in
                candidates(path: path, slot: slot, words: words, index: index, prefix: prefix)
            }
        }
    }

    static func parameter(_ slot: Slot, in spec: CommandSpec) -> ParameterSpec? {
        switch slot {
        case .operand(let index): spec.operands[safe: index]
        case .option(let name): spec.options.first { $0.name == name }
        }
    }

    /// Candidates formatted for the requesting shell.
    static func candidates(path: [String], slot: Slot, words: [String], index: Int, prefix: String, shell: CompletionShell? = CompletionShell.requesting) -> [String] {
        guard let spec = CommandHelp.spec(path), let parameter = parameter(slot, in: spec) else { return [] }
        let line = Line(words: words, before: index, spec: spec)
        let context = LocalizationContext.commandLine(language: line.options["--language"].flatMap { LocalizationContext.commandLineLanguages.contains($0) ? $0 : nil })
        let items = LocalizationContext.$current.withValue(context) {
            (try? suggestions(for: parameter, in: spec, line: line, typed: unquote(prefix))) ?? []
        }
        return items.map { value, description in
            let description = description.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
            switch shell {
            case .zsh?:
                // _describe splits value and description at the first unescaped colon.
                let value = value.replacingOccurrences(of: ":", with: "\\:")
                return description.isEmpty ? value : value + ":" + description
            case .fish?: return description.isEmpty ? value : value + "\t" + description
            default:
                // compgen -W expands each word, so quote what it would expand.
                return String(value.flatMap { "\\$`\"'{}~".contains($0) ? ["\\", $0] : [$0] })
            }
        }
    }

    /// What the command line already says before the word being completed.
    struct Line {
        var positionals: [String] = []
        var options: [String: String] = [:]

        init(words: [String], before end: Int, spec: CommandSpec) {
            let valued = Set(spec.options.filter { $0.type != "bool" }.map { "--" + $0.name }).union(CommonOptions.valued)
            let words = Array(words.prefix(max(0, end))).map(CommandCompletion.unquote)
            var remaining = spec.path[...], index = 1, terminated = false
            while index < words.count {
                let word = words[index]; index += 1
                if terminated { positionals.append(word); continue }
                if word == "--" { terminated = true; continue }
                if word.hasPrefix("-") && word != "-" {
                    let name = CommandLineInvocation.optionName(word)
                    guard valued.contains(name) else { continue }
                    if let separator = word.firstIndex(of: "=") { options[name] = String(word[word.index(after: separator)...]); continue }
                    // bash splits --option=value into three words.
                    if index < words.count, words[index] == "=" { index += 1 }
                    if index < words.count { options[name] = words[index]; index += 1 }
                    continue
                }
                if positionals.isEmpty, remaining.first == word { remaining.removeFirst(); continue }
                positionals.append(word)
            }
        }

        var paths: LauncherPaths {
            let typed = options["--data-dir"].map { $0.hasPrefix("~/") ? NSHomeDirectory() + $0.dropFirst() : $0 }
            return LauncherPaths(root: (typed ?? ProcessInfo.processInfo.environment["RURI_DATA_DIR"]).map { URL(fileURLWithPath: $0) })
        }
    }

    private static func suggestions(for parameter: ParameterSpec, in spec: CommandSpec, line: Line, typed: String) throws -> [(String, String)] {
        let catalog = TargetCatalog(paths: line.paths)
        func operand(_ role: ParameterRole) -> String? {
            spec.operands.firstIndex { $0.role == role }.flatMap { line.positionals[safe: $0] }
        }
        switch parameter.role {
        case .instance: return targets(try catalog.index(.instance), typed: typed)
        case .preferredInstance: return [("none", "")] + targets(try catalog.index(.instance), typed: typed)
        case .directory: return targets(try catalog.index(.directory), typed: typed)
        case .account: return targets(try catalog.index(.account), typed: typed)
        case .session:
            guard let reference = operand(.instance), let instance = UUID(uuidString: try catalog.resolve(reference, as: .instance)) else { return [] }
            return targets(try catalog.index(.session, instance: instance), typed: typed)
        case .recoveryTarget:
            return targets(try catalog.index(line.positionals.first == "repository-import" ? .directory : .instance), typed: typed)
        case .scope:
            let instances = targets(try catalog.index(.instance), typed: typed.hasPrefix("instance:") ? String(typed.dropFirst(9)) : "")
            return [("app", ""), ("defaults", "")] + instances.map { ("instance:" + $0.0, $0.1) }
        case .configKey, .configGroup, .configValue:
            let scope = line.options["--scope"]
            let fields = scope == "app" ? ConfigurationService.appFields : scope == nil ? ConfigurationService.appFields + ConfigurationService.launchFields : ConfigurationService.launchFields
            if parameter.role == .configGroup { return ConfigurationService.groups.map { ($0, "") } }
            if parameter.role == .configValue {
                guard let field = operand(.configKey).flatMap({ key in fields.first { $0.name == key } }) else { return [] }
                return (field.type == "boolean" ? ["true", "false"] : field.values).map { ($0, "") } + (field.nullable ? [("null", "")] : [])
            }
            let described = try fields.map { field in (field.name, CommandTextRenderer.fieldDescription(try Value.encode(field))) }
            return described + (scope == "app" ? [] : ConfigurationService.groups.map { ($0, "") })
        case .commandPath:
            guard case .some(let index) = spec.operands.firstIndex(where: { $0.name == parameter.name }) else { return [] }
            return CommandHelp.subcommands(Array(line.positionals.prefix(index))).compactMap { command in
                command.configuration.commandName.map { ($0, command.configuration.abstract) }
            }
        default: return []
        }
    }

    /// References that resolve to each entry. While an ID prefix is being
    /// typed, the matching entries also complete to their short IDs.
    static func targets(_ index: TargetIndex, typed: String) -> [(String, String)] {
        let hex = TargetIndex.hex(typed)
        return index.entries.flatMap { entry -> [(String, String)] in
            let reference = index.reference(entry)
            let name = entry.name.flatMap { reference == $0 || reference == "name:" + $0 ? nil : $0 }
            let description = [name ?? "", entry.detail].filter { !$0.isEmpty }.joined(separator: " · ")
            var items = [(reference, description)]
            if let hex, !typed.isEmpty, !reference.hasPrefix(typed), TargetIndex.compact(entry.id).hasPrefix(hex) {
                let id: String
                if typed.contains("-") { id = typed + entry.id.uuidString.lowercased().dropFirst(typed.count) }
                else { id = typed + TargetIndex.compact(entry.id).dropFirst(typed.count).prefix(max(0, index.shortID(entry.id).count - typed.count)) }
                if (try? index.resolve(id)) == entry.id.uuidString { items.append((id, description)) }
            }
            return items
        }
    }

    /// Shell words arrive verbatim, with their quotes and escapes.
    static func unquote(_ word: String) -> String {
        var result = "", quote: Character?, escaped = false
        for character in word {
            if escaped { result.append(character); escaped = false; continue }
            switch (quote, character) {
            case (nil, "\\"), ("\"", "\\"): escaped = true
            case (nil, "'"), (nil, "\""): quote = character
            case ("'", "'"), ("\"", "\""): quote = nil
            default: result.append(character)
            }
        }
        return result
    }
}
