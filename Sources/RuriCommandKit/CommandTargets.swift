import Foundation
import RuriCore
import RuriLocalization

/// One local resource a command can name.
struct TargetEntry: Sendable {
    let id: UUID
    /// Sessions and the default directory have no name to type.
    let name: String?
    var detail = ""
}

/// Every resource of one kind, so a reference can be checked against all of
/// them, not only those on the current page. Resolution, short IDs and
/// completion share it, so a reference shown in one always works in another.
struct TargetIndex: Sendable {
    enum Kind: Sendable { case instance, directory, account, session }
    static let minimumPrefix = 8

    let kind: Kind
    let entries: [TargetEntry]
    /// The list command that shows the candidates, for a missing target.
    var listCommand: [String] = []

    /// A full UUID as typed, `default` for the default directory, or the ID of
    /// the one entry with that exact name or ID prefix. `name:` and `id:` choose
    /// one interpretation when a name looks like an ID prefix.
    func resolve(_ input: String) throws -> String {
        if UUID(uuidString: input) != nil || isDefault(input) { return input }
        let matches: [TargetEntry]
        if input.hasPrefix("id:") {
            let value = String(input.dropFirst(3))
            if UUID(uuidString: value) != nil { return value }
            guard let prefix = Self.hex(value), prefix.count >= Self.minimumPrefix else {
                throw OperationFailure("INVALID_ARGUMENT", Messages.CLIExperience.idPrefixTooShort(input).localized)
            }
            matches = entries.filter { Self.compact($0.id).hasPrefix(prefix) }
        } else if input.hasPrefix("name:") {
            let name = String(input.dropFirst(5))
            matches = entries.filter { $0.name == name }
        } else {
            let prefix = Self.hex(input).flatMap { $0.count >= Self.minimumPrefix ? $0 : nil }
            matches = entries.filter { entry in entry.name == input || prefix.map { Self.compact(entry.id).hasPrefix($0) } == true }
        }
        guard !matches.isEmpty else { throw notFound(input) }
        guard matches.count == 1 else { throw ambiguous(input, matches) }
        return matches[0].id.uuidString
    }

    /// The shortest ID prefix, from eight characters, that names only this
    /// entry and is not also a name.
    func shortID(_ id: UUID) -> String {
        let full = Self.compact(id), others = entries.filter { $0.id != id }.map { Self.compact($0.id) }
        let names = Set(entries.compactMap(\.name))
        for length in Self.minimumPrefix..<full.count {
            let prefix = String(full.prefix(length))
            if !others.contains(where: { $0.hasPrefix(prefix) }) && !names.contains(prefix) && !isDefault(prefix) { return prefix }
        }
        return id.uuidString.lowercased()
    }

    /// What to type for an entry: its name when that alone resolves to it,
    /// `name:<name>` when the name could be read otherwise, else its short ID.
    func reference(_ entry: TargetEntry) -> String {
        if kind == .directory && entry.id == GameDirectory.defaultID { return "default" }
        guard let name = entry.name, !name.isEmpty, entries.filter({ $0.name == name }).count == 1 else { return shortID(entry.id) }
        if !name.hasPrefix("-"), (try? resolve(name)) == entry.id.uuidString { return name }
        return "name:" + name
    }

    private func isDefault(_ input: String) -> Bool { kind == .directory && input == "default" }

    private func notFound(_ input: String) -> OperationFailure {
        let message: LocalizedMessage
        switch kind {
        case .instance: message = Messages.CLIExperience.noInstanceMatches(input)
        case .directory: message = Messages.CLIExperience.noDirectoryMatches(input)
        case .account: message = Messages.CLIExperience.noAccountMatches(input)
        case .session: message = Messages.CLIExperience.noSessionMatches(input)
        }
        return OperationFailure("NOT_FOUND", message.localized, nextActions: listCommand.isEmpty ? [] : [.init(listCommand)])
    }

    private func ambiguous(_ input: String, _ matches: [TargetEntry]) -> OperationFailure {
        let message: LocalizedMessage
        switch kind {
        case .instance: message = Messages.CLIExperience.ambiguousInstanceTarget(input)
        case .directory: message = Messages.CLIExperience.ambiguousDirectoryTarget(input)
        case .account: message = Messages.CLIExperience.ambiguousAccountTarget(input)
        case .session: message = Messages.CLIExperience.ambiguousSessionTarget(input)
        }
        let candidates = matches.map { entry -> Value in
            var fields: [String: Value] = ["id": .string(entry.id.uuidString), "shortID": .string(shortID(entry.id))]
            if let name = entry.name { fields["name"] = .string(name) }
            return .object(fields)
        }
        return OperationFailure("AMBIGUOUS_TARGET", message.localized, details: .array(candidates))
    }

    static func compact(_ id: UUID) -> String { id.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }

    /// Lowercase hexadecimal without hyphens, or nil for anything else.
    static func hex(_ text: String) -> String? {
        let value = text.lowercased().replacingOccurrences(of: "-", with: "")
        guard !value.isEmpty, value.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        return value
    }
}

/// Indexes of one data directory, read once and only when a reference needs them.
/// Nothing here writes, migrates or repairs state.
final class TargetCatalog {
    let paths: LauncherPaths
    private var loaded: PersistentState?

    init(paths: LauncherPaths) { self.paths = paths }

    func state() throws -> PersistentState {
        if let loaded { return loaded }
        let state = try StateStore.load(paths); loaded = state; return state
    }

    func index(_ kind: TargetIndex.Kind, instance: UUID? = nil) throws -> TargetIndex {
        switch kind {
        case .instance:
            let entries = try state().instances.map { item in
                TargetEntry(id: item.id, name: item.name, detail: ([item.gameVersion] + item.loaderSelections.map(\.loader.rawValue)).joined(separator: " "))
            }
            return .init(kind: kind, entries: entries, listCommand: ["instance", "list"])
        case .directory:
            let state = try state()
            let saved = (state.gameDirectories ?? []) + (state.detachedMinecraftFolders ?? []).map(\.directory)
            let entries = [TargetEntry(id: GameDirectory.defaultID, name: nil, detail: paths.root.path)] + saved.map { TargetEntry(id: $0.id, name: $0.name, detail: $0.url.path) }
            return .init(kind: kind, entries: entries, listCommand: ["directory", "list"])
        case .account:
            let entries = try state().accounts.map { TargetEntry(id: $0.id, name: $0.username, detail: $0.kind.rawValue) }
            return .init(kind: kind, entries: entries, listCommand: ["account", "list"])
        case .session:
            guard let instance else { return .init(kind: kind, entries: []) }
            let format = Date.FormatStyle(date: .numeric, time: .shortened)
            let entries = try GameHistoryStore.references(paths: paths, instanceID: instance).map { TargetEntry(id: $0.id, name: nil, detail: $0.createdAt.formatted(format)) }
            return .init(kind: kind, entries: entries, listCommand: ["session", "list", "--instance", instance.uuidString])
        }
    }

    func resolve(_ input: String, as kind: TargetIndex.Kind, instance: UUID? = nil) throws -> String {
        // A full ID needs no lookup, so records of removed instances stay reachable.
        if UUID(uuidString: input) != nil || (kind == .directory && input == "default") { return input }
        return try index(kind, instance: instance).resolve(input)
    }
}

enum CommandTargets {
    /// The request with every instance, directory, account and session
    /// reference replaced by its canonical ID, before any command logic runs.
    static func resolve(_ request: CommandRequest) throws -> CommandRequest {
        let catalog = TargetCatalog(paths: CLIApplication.basePaths(request))
        var operands = request.operands, options = request.options
        var instance: UUID?
        for (index, parameter) in request.spec.operands.enumerated() where operands.indices.contains(index) {
            let value = operands[index]
            switch parameter.role {
            case .instance:
                operands[index] = try catalog.resolve(value, as: .instance); instance = UUID(uuidString: operands[index])
            case .directory: operands[index] = try catalog.resolve(value, as: .directory)
            case .account: operands[index] = try catalog.resolve(value, as: .account)
            case .session: operands[index] = try catalog.resolve(value, as: .session, instance: instance)
            case .recoveryTarget: operands[index] = try catalog.resolve(value, as: operands.first == "repository-import" ? .directory : .instance)
            default: break
            }
        }
        for parameter in request.spec.options {
            guard case .string(let value) = options[parameter.name] else { continue }
            switch parameter.role {
            case .instance: options[parameter.name] = .string(try catalog.resolve(value, as: .instance))
            case .directory: options[parameter.name] = .string(try catalog.resolve(value, as: .directory))
            case .account: options[parameter.name] = .string(try catalog.resolve(value, as: .account))
            case .preferredInstance where value != "none": options[parameter.name] = .string(try catalog.resolve(value, as: .instance))
            case .scope where value.hasPrefix("instance:"):
                options[parameter.name] = .string("instance:" + (try catalog.resolve(String(value.dropFirst(9)), as: .instance)))
            default: break
            }
        }
        return .init(spec: request.spec, common: request.common, operands: operands, options: options)
    }
}
