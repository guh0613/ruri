import RuriLocalization
import ArgumentParser
import Foundation
import RuriCore

struct SchemaCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["schema"], summary: Messages.CLIInterface.tfd63207de5ca.localized, operands: [
        .init(name: "resource", type: "string", required: false, help: "resource"),
        .init(name: "action", type: "string", required: false, help: "action"),
        .init(name: "subaction", type: "string", required: false, help: "subaction")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t907f38578610.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppInfoCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["app","info"], summary: Messages.CLIInterface.t04f3e8ad5625.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageGetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["app","language","get"], summary: Messages.CLIInterface.t0adf2f545bf7.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageSetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["app","language","set"], summary: Messages.CLIInterface.t56774fcdd554.localized, operands: [
        .init(name: "language", type: "string", required: true, help: "language")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "language") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CliStatusCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["cli","status"], summary: Messages.CLIInterface.tb15b5698e07c.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct CliInstallCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["cli","install"], summary: Messages.CLIInterface.t05715f352213.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.t6edc04f9cc0c.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.t6edc04f9cc0c.localized)) var optionBinDir: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CliUninstallCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["cli","uninstall"], summary: Messages.CLIInterface.t32373072cae3.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.t7736b5280e58.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.t7736b5280e58.localized)) var optionBinDir: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AppLanguageGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "language", abstract: Messages.CLIInterface.teaca59ff6999.localized, subcommands: [AppLanguageGetCommand.self, AppLanguageSetCommand.self])
}

struct AppGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "app", abstract: Messages.CLIInterface.t64c4a55a8346.localized, subcommands: [AppInfoCommand.self, AppLanguageGroup.self])
}

struct CliGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cli", abstract: Messages.CLIInterface.td9fc3f8ff28d.localized, subcommands: [CliStatusCommand.self, CliInstallCommand.self, CliUninstallCommand.self])
}

struct RuriCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ruri", abstract: Messages.CLIInterface.ta03f160849e6.localized, version: BuildConfiguration().version, subcommands: [SchemaCommand.self, AppGroup.self, CliGroup.self])
}

enum CommandRegistry {
    static let commands: [CommandSpec] = [SchemaCommand.spec, AppInfoCommand.spec, AppLanguageGetCommand.spec, AppLanguageSetCommand.spec, CliStatusCommand.spec, CliInstallCommand.spec, CliUninstallCommand.spec]
}

