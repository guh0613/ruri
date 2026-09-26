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

struct ConfigGetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["config","get"], summary: Messages.CLIInterface.t9b80abd0b1ac.localized, operands: [
        .init(name: "key", type: "string", required: false, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "show-secrets", type: "bool", required: false, help: Messages.CLIInterface.t9180c54b32fc.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "key?") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.t9f1f1df0e83d.localized)) var optionScope: String?
    @Flag(name: .customLong("show-secrets"), help: ArgumentHelp(Messages.CLIInterface.t9180c54b32fc.localized)) var optionShowSecrets = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "show-secrets": .bool(optionShowSecrets)
    ].filter { $0.value != .null } }
}

struct ConfigSetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["config","set"], summary: Messages.CLIInterface.t51d568cf62ef.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key"),
        .init(name: "value", type: "string", required: true, help: "value")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t3a7dba9c3050.localized)) var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.t9f1f1df0e83d.localized)) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.tc865886779a0.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigApplyCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["config","apply"], summary: Messages.CLIInterface.t22ad2905d16d.localized, operands: [

    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.t149625e63af0.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.t9f1f1df0e83d.localized)) var optionScope: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.t149625e63af0.localized)) var optionFile: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.tc865886779a0.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "file": .text(optionFile),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigResetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["config","reset"], summary: Messages.CLIInterface.t620fab80a2bb.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "key") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.t9f1f1df0e83d.localized)) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.tc865886779a0.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigInheritCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["config","inherit"], summary: Messages.CLIInterface.te7f60fe2aebd.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "key") var operands: [String] = []
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.t9f1f1df0e83d.localized)) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.tc865886779a0.localized)) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AppLanguageGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "language", abstract: Messages.CLIInterface.teaca59ff6999.localized, subcommands: [AppLanguageGetCommand.self, AppLanguageSetCommand.self])
}

struct ConfigGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "config", abstract: Messages.CLIInterface.t1fcd3e7a6ffc.localized, subcommands: [ConfigGetCommand.self, ConfigSetCommand.self, ConfigApplyCommand.self, ConfigResetCommand.self, ConfigInheritCommand.self])
}

struct AppGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "app", abstract: Messages.CLIInterface.t64c4a55a8346.localized, subcommands: [AppInfoCommand.self, AppLanguageGroup.self])
}

struct CliGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cli", abstract: Messages.CLIInterface.td9fc3f8ff28d.localized, subcommands: [CliStatusCommand.self, CliInstallCommand.self, CliUninstallCommand.self])
}

struct RuriCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ruri", abstract: Messages.CLIInterface.ta03f160849e6.localized, version: BuildConfiguration().version, subcommands: [SchemaCommand.self, AppGroup.self, CliGroup.self, ConfigGroup.self])
}

enum CommandRegistry {
    static let commands: [CommandSpec] = [SchemaCommand.spec, AppInfoCommand.spec, AppLanguageGetCommand.spec, AppLanguageSetCommand.spec, CliStatusCommand.spec, CliInstallCommand.spec, CliUninstallCommand.spec, ConfigGetCommand.spec, ConfigSetCommand.spec, ConfigApplyCommand.spec, ConfigResetCommand.spec, ConfigInheritCommand.spec]
}

