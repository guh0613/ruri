import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

struct ServerListCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "list"], summary: Messages.CLIInterface.serverListHelp.localized, operands: [
    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.serverInstanceOptionHelp.localized, values: [], role: .instance),
        .init(name: "search", type: "string", required: false, help: Messages.CLIInterface.serverSearchHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, examples: ["ruri server list", "ruri server list --instance Survival"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.serverInstanceOptionHelp.localized), completion: Self.completion(option: "instance")) var optionInstance: String?
    @Option(name: .customLong("search"), help: ArgumentHelp(Messages.CLIInterface.serverSearchHelp.localized), completion: Self.completion(option: "search")) var optionSearch: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { ["instance": .text(optionInstance), "search": .text(optionSearch), "limit": optionLimit.map(Value.integer) ?? .null, "offset": optionOffset.map(Value.integer) ?? .null, "all": .bool(optionAll)].filter { $0.value != .null } }
}

struct ServerAddCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "add"], summary: Messages.CLIInterface.serverAddHelp.localized, operands: [
        .init(name: "address", type: "string", required: true, help: Messages.CLIInterface.argumentServerAddress.localized, values: [], role: .text)
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.serverNameHelp.localized, values: []),
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.serverInstanceOptionHelp.localized, values: [], role: .instance),
        .init(name: "resource-packs", type: "string", required: false, help: Messages.CLIInterface.serverResourcePacksHelp.localized, values: ["ask", "always", "never"], defaultValue: "ask"),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, examples: ["ruri server add play.example.com --name Example", "ruri server add play.example.com --instance Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAddress: String?
    var operands: [String] { [argumentAddress].compactMap { $0 } }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.serverNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.serverInstanceOptionHelp.localized), completion: Self.completion(option: "instance")) var optionInstance: String?
    @Option(name: .customLong("resource-packs"), help: ArgumentHelp(Messages.CLIInterface.serverResourcePacksHelp.localized), completion: Self.completion(option: "resource-packs")) var optionResourcePacks: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["name": .text(optionName), "instance": .text(optionInstance), "resource-packs": .text(optionResourcePacks), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerEditCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "edit"], summary: Messages.CLIInterface.serverEditHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "entry", type: "string", required: true, help: Messages.CLIInterface.argumentServerEntry.localized, values: [], role: .text)
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.serverNameHelp.localized, values: []),
        .init(name: "address", type: "string", required: false, help: Messages.CLIInterface.serverAddressHelp.localized, values: []),
        .init(name: "resource-packs", type: "string", required: false, help: Messages.CLIInterface.serverResourcePacksHelp.localized, values: ["ask", "always", "never"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, examples: ["ruri server edit Survival 0 --name Lobby"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentEntry: String?
    var operands: [String] { [argumentInstance, argumentEntry].compactMap { $0 } }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.serverNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("address"), help: ArgumentHelp(Messages.CLIInterface.serverAddressHelp.localized), completion: Self.completion(option: "address")) var optionAddress: String?
    @Option(name: .customLong("resource-packs"), help: ArgumentHelp(Messages.CLIInterface.serverResourcePacksHelp.localized), completion: Self.completion(option: "resource-packs")) var optionResourcePacks: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["name": .text(optionName), "address": .text(optionAddress), "resource-packs": .text(optionResourcePacks), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "remove"], summary: Messages.CLIInterface.serverRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "entry", type: "string", required: true, help: Messages.CLIInterface.argumentServerEntry.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, examples: ["ruri server remove Survival 0 --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentEntry: String?
    var operands: [String] { [argumentInstance, argumentEntry].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { ["dry-run": .bool(optionDryRun), "yes": .bool(optionYes)].filter { $0.value != .null } }
}

struct ServerMoveCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "move"], summary: Messages.CLIInterface.serverMoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "entry", type: "string", required: true, help: Messages.CLIInterface.argumentServerEntry.localized, values: [], role: .text),
        .init(name: "position", type: "string", required: true, help: Messages.CLIInterface.argumentServerPosition.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, examples: ["ruri server move Survival 2 0"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentEntry: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentPosition: String?
    var operands: [String] { [argumentInstance, argumentEntry, argumentPosition].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerFavoriteCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "favorite"], summary: Messages.CLIInterface.serverFavoriteHelp.localized, operands: [
        .init(name: "address", type: "string", required: true, help: Messages.CLIInterface.argumentServerAddress.localized, values: [], role: .text)
    ], options: [
        .init(name: "value", type: "string", required: true, help: Messages.CLIInterface.serverFavoriteValueHelp.localized, values: ["true", "false"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, examples: ["ruri server favorite play.example.com --value true"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAddress: String?
    var operands: [String] { [argumentAddress].compactMap { $0 } }
    @Option(name: .customLong("value"), help: ArgumentHelp(Messages.CLIInterface.serverFavoriteValueHelp.localized), completion: Self.completion(option: "value")) var optionValue: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["value": .text(optionValue), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerPreferencesCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "preferences"], summary: Messages.CLIInterface.serverPreferencesHelp.localized, operands: [
        .init(name: "address", type: "string", required: true, help: Messages.CLIInterface.argumentServerAddress.localized, values: [], role: .text)
    ], options: [
        .init(name: "alias", type: "string", required: false, help: Messages.CLIInterface.serverAliasHelp.localized, values: []),
        .init(name: "notes", type: "string", required: false, help: Messages.CLIInterface.serverNotesHelp.localized, values: []),
        .init(name: "preferred-instance", type: "string", required: false, help: Messages.CLIInterface.serverPreferredInstanceHelp.localized, values: [], role: .preferredInstance),
        .init(name: "saved", type: "string", required: false, help: Messages.CLIInterface.serverSavedHelp.localized, values: ["true", "false"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, examples: ["ruri server preferences play.example.com --preferred-instance Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAddress: String?
    var operands: [String] { [argumentAddress].compactMap { $0 } }
    @Option(name: .customLong("alias"), help: ArgumentHelp(Messages.CLIInterface.serverAliasHelp.localized), completion: Self.completion(option: "alias")) var optionAlias: String?
    @Option(name: .customLong("notes"), help: ArgumentHelp(Messages.CLIInterface.serverNotesHelp.localized), completion: Self.completion(option: "notes")) var optionNotes: String?
    @Option(name: .customLong("preferred-instance"), help: ArgumentHelp(Messages.CLIInterface.serverPreferredInstanceHelp.localized), completion: Self.completion(option: "preferred-instance")) var optionPreferredInstance: String?
    @Option(name: .customLong("saved"), help: ArgumentHelp(Messages.CLIInterface.serverSavedHelp.localized), completion: Self.completion(option: "saved")) var optionSaved: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["alias": .text(optionAlias), "notes": .text(optionNotes), "preferred-instance": .text(optionPreferredInstance), "saved": .text(optionSaved), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerQueryCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "query"], summary: Messages.CLIInterface.serverQueryHelp.localized, operands: [
        .init(name: "address", type: "string", required: true, help: Messages.CLIInterface.argumentServerAddress.localized, values: [], role: .text)
    ], options: [
    ], mutation: false, confirmation: false, examples: ["ruri server query play.example.com"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAddress: String?
    var operands: [String] { [argumentAddress].compactMap { $0 } }
    var parameters: [String: Value] { [:].filter { $0.value != .null } }
}

struct ServerGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { .init(commandName: "server", abstract: Messages.CLIInterface.serverCommands.localized, subcommands: [ServerListCommand.self, ServerAddCommand.self, ServerEditCommand.self, ServerRemoveCommand.self, ServerMoveCommand.self, ServerFavoriteCommand.self, ServerPreferencesCommand.self, ServerQueryCommand.self]) }
}
