import ArgumentParser
import Foundation
import RuriCore
import RuriLocalization

struct ServerListCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "list"], summary: Messages.Servers.all.localized, operands: [
    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.Servers.instanceName.localized, values: []),
        .init(name: "search", type: "string", required: false, help: Messages.Servers.search.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.Servers.all.localized, values: [])
    ], mutation: false, confirmation: false) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.Servers.instanceName.localized)) var optionInstance: String?
    @Option(name: .customLong("search"), help: ArgumentHelp(Messages.Servers.search.localized)) var optionSearch: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.Servers.all.localized)) var optionAll = false
    var parameters: [String: Value] { ["instance": .text(optionInstance), "search": .text(optionSearch), "limit": optionLimit.map(Value.integer) ?? .null, "offset": optionOffset.map(Value.integer) ?? .null, "all": .bool(optionAll)].filter { $0.value != .null } }
}

struct ServerAddCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "add"], summary: Messages.Servers.add.localized, operands: [
        .init(name: "address", type: "string", required: true, help: "address")
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.Servers.name.localized, values: []),
        .init(name: "instance", type: "string", required: false, help: Messages.Servers.instanceName.localized, values: []),
        .init(name: "resource-packs", type: "string", required: false, help: Messages.Servers.resourcePacks.localized, values: ["ask", "always", "never"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.Servers.name.localized)) var optionName: String?
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.Servers.instanceName.localized)) var optionInstance: String?
    @Option(name: .customLong("resource-packs"), help: ArgumentHelp(Messages.Servers.resourcePacks.localized)) var optionResourcePacks: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["name": .text(optionName), "instance": .text(optionInstance), "resource-packs": .text(optionResourcePacks), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerEditCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "edit"], summary: Messages.Servers.edit.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "entry", type: "string", required: true, help: "entry")
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.Servers.name.localized, values: []),
        .init(name: "address", type: "string", required: false, help: Messages.Servers.address.localized, values: []),
        .init(name: "resource-packs", type: "string", required: false, help: Messages.Servers.resourcePacks.localized, values: ["ask", "always", "never"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.Servers.name.localized)) var optionName: String?
    @Option(name: .customLong("address"), help: ArgumentHelp(Messages.Servers.address.localized)) var optionAddress: String?
    @Option(name: .customLong("resource-packs"), help: ArgumentHelp(Messages.Servers.resourcePacks.localized)) var optionResourcePacks: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["name": .text(optionName), "address": .text(optionAddress), "resource-packs": .text(optionResourcePacks), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "remove"], summary: Messages.Servers.remove.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "entry", type: "string", required: true, help: "entry")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.Servers.confirmRemove.localized, values: [])
    ], mutation: true, confirmation: true) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.Servers.confirmRemove.localized)) var optionYes = false
    var parameters: [String: Value] { ["dry-run": .bool(optionDryRun), "yes": .bool(optionYes)].filter { $0.value != .null } }
}

struct ServerMoveCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "move"], summary: Messages.Servers.manage.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "entry", type: "string", required: true, help: "entry"),
        .init(name: "position", type: "string", required: true, help: "position")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerFavoriteCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "favorite"], summary: Messages.Servers.favorite.localized, operands: [
        .init(name: "address", type: "string", required: true, help: "address")
    ], options: [
        .init(name: "value", type: "string", required: true, help: Messages.Servers.favorite.localized, values: ["true", "false"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Option(name: .customLong("value"), help: ArgumentHelp(Messages.Servers.favorite.localized)) var optionValue: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["value": .text(optionValue), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerPreferencesCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "preferences"], summary: Messages.Servers.globalSettings.localized, operands: [
        .init(name: "address", type: "string", required: true, help: "address")
    ], options: [
        .init(name: "alias", type: "string", required: false, help: Messages.Servers.alias.localized, values: []),
        .init(name: "notes", type: "string", required: false, help: Messages.Servers.notes.localized, values: []),
        .init(name: "preferred-instance", type: "string", required: false, help: Messages.Servers.preferredInstance.localized, values: []),
        .init(name: "saved", type: "string", required: false, help: Messages.Servers.savedInLibrary.localized, values: ["true", "false"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    @Option(name: .customLong("alias"), help: ArgumentHelp(Messages.Servers.alias.localized)) var optionAlias: String?
    @Option(name: .customLong("notes"), help: ArgumentHelp(Messages.Servers.notes.localized)) var optionNotes: String?
    @Option(name: .customLong("preferred-instance"), help: ArgumentHelp(Messages.Servers.preferredInstance.localized)) var optionPreferredInstance: String?
    @Option(name: .customLong("saved"), help: ArgumentHelp(Messages.Servers.savedInLibrary.localized)) var optionSaved: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { ["alias": .text(optionAlias), "notes": .text(optionNotes), "preferred-instance": .text(optionPreferredInstance), "saved": .text(optionSaved), "dry-run": .bool(optionDryRun)].filter { $0.value != .null } }
}

struct ServerQueryCommand: ExecutableCommand {
    static var spec: CommandSpec { .init(path: ["server", "query"], summary: Messages.Servers.probe.localized, operands: [
        .init(name: "address", type: "string", required: true, help: "address")
    ], options: [
    ], mutation: false, confirmation: false) }
    @OptionGroup var common: CommonOptions
    @Argument var operands: [String] = []
    var parameters: [String: Value] { [:].filter { $0.value != .null } }
}

struct ServerGroup: ParsableCommand {
    static var configuration: CommandConfiguration { .init(commandName: "server", abstract: Messages.Servers.page.localized, subcommands: [ServerListCommand.self, ServerAddCommand.self, ServerEditCommand.self, ServerRemoveCommand.self, ServerMoveCommand.self, ServerFavoriteCommand.self, ServerPreferencesCommand.self, ServerQueryCommand.self]) }
}
