import RuriLocalization
import ArgumentParser
import Foundation
import RuriCore

struct SchemaCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schema"], summary: Messages.CLIInterface.tfd63207de5ca.localized, operands: [
        .init(name: "resource", type: "string", required: false, help: "resource"),
        .init(name: "action", type: "string", required: false, help: "action"),
        .init(name: "subaction", type: "string", required: false, help: "subaction")
    ], options: [
        .init(name: "input", type: "bool", required: false, help: Messages.CLIExperience.inputSchema.localized),
        .init(name: "output-schema", type: "bool", required: false, help: Messages.CLIExperience.outputSchema.localized),
        .init(name: "scope", type: "string", required: false, help: Messages.CLIExperience.schemaScope.localized, values: ["app", "defaults", "instance"]),
        .init(name: "full", type: "bool", required: false, help: Messages.CLIExperience.fullSchema.localized)
    ], examples: ["ruri schema config apply --input --scope instance --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t907f38578610.localized)) var operands: [String] = []
    @Flag(help: ArgumentHelp(Messages.CLIExperience.inputSchema.localized)) var input = false
    @Flag(name: .customLong("output-schema"), help: ArgumentHelp(Messages.CLIExperience.outputSchema.localized)) var outputSchema = false
    @Option(help: ArgumentHelp(Messages.CLIExperience.schemaScope.localized)) var scope: String?
    @Flag(help: ArgumentHelp(Messages.CLIExperience.fullSchema.localized)) var full = false
    var parameters: [String: Value] { ["input": .bool(input), "output-schema": .bool(outputSchema), "scope": .text(scope), "full": .bool(full)].filter { $0.value != .null } }
}

struct AppInfoCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","info"], summary: Messages.CLIInterface.t04f3e8ad5625.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","language","get"], summary: Messages.CLIInterface.t0adf2f545bf7.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","language","set"], summary: Messages.CLIInterface.t56774fcdd554.localized, operands: [
        .init(name: "language", type: "string", required: true, help: "language")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "language") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CliStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","status"], summary: Messages.CLIInterface.tb15b5698e07c.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.t7736b5280e58.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.t7736b5280e58.localized)) var optionBinDir: String?
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir)
    ].filter { $0.value != .null } }
}

struct CliInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","install"], summary: Messages.CLIInterface.t05715f352213.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.t6edc04f9cc0c.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: []) }
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
    static var spec: CommandSpec { CommandSpec(path: ["cli","uninstall"], summary: Messages.CLIInterface.t32373072cae3.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.t7736b5280e58.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: true, examples: []) }
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
    static var spec: CommandSpec { CommandSpec(path: ["config","get"], summary: Messages.CLIInterface.t9b80abd0b1ac.localized, operands: [
        .init(name: "key", type: "string", required: false, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "show-secrets", type: "bool", required: false, help: Messages.CLIInterface.t9180c54b32fc.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
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
    static var spec: CommandSpec { CommandSpec(path: ["config","set"], summary: Messages.CLIInterface.t51d568cf62ef.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key"),
        .init(name: "value", type: "string", required: true, help: "value")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config set memory.maximumMB 6144 --scope defaults --json"]) }
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
    static var spec: CommandSpec { CommandSpec(path: ["config","apply"], summary: Messages.CLIInterface.t22ad2905d16d.localized, operands: [

    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.t149625e63af0.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config apply --scope instance:<uuid> --file patch.json --dry-run --json"]) }
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
    static var spec: CommandSpec { CommandSpec(path: ["config","reset"], summary: Messages.CLIInterface.t620fab80a2bb.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
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
    static var spec: CommandSpec { CommandSpec(path: ["config","inherit"], summary: Messages.CLIInterface.te7f60fe2aebd.localized, operands: [
        .init(name: "key", type: "string", required: true, help: "key")
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.t9f1f1df0e83d.localized, values: []),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.tc865886779a0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config inherit memory --scope instance:<uuid> --json"]) }
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

struct InstanceListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","list"], summary: Messages.CLIInterface.t163f689a3d2f.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.t61c2b6ad309c.localized, values: []),
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.t3a0b2a4eac30.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.t61c2b6ad309c.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.t3a0b2a4eac30.localized)) var optionDirectory: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceSelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","selected"], summary: Messages.CLIInterface.t1a9316dc0247.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","show"], summary: Messages.CLIInterface.td25fbbc9aa83.localized, operands: [
        .init(name: "id", type: "string", required: false, help: "id")
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.t554bb290d490.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id?") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.t554bb290d490.localized)) var optionName: String?
    var parameters: [String: Value] { [
        "name": .text(optionName)
    ].filter { $0.value != .null } }
}

struct InstanceVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","versions"], summary: Messages.CLIInterface.t309b2060e6e7.localized, operands: [

    ], options: [
        .init(name: "snapshots", type: "bool", required: false, help: Messages.CLIInterface.t0f6dcda14ae4.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Flag(name: .customLong("snapshots"), help: ArgumentHelp(Messages.CLIInterface.t0f6dcda14ae4.localized)) var optionSnapshots = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "snapshots": .bool(optionSnapshots),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceCreateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","create"], summary: Messages.CLIInterface.tea647925f201.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.tf78b43b0ee95.localized, values: []),
        .init(name: "game", type: "string", required: true, help: Messages.CLIInterface.tc32a76745397.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tcba396edfba1.localized, values: []),
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.tc54f734a37a6.localized, values: []),
        .init(name: "no-install", type: "bool", required: false, help: Messages.CLIInterface.td183fd7d75d0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance create --name Survival --game 1.21.1 --directory default --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.tf78b43b0ee95.localized)) var optionName: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.tc32a76745397.localized)) var optionGame: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tcba396edfba1.localized)) var optionDirectory: String?
    @Option(name: .customLong("component"), help: ArgumentHelp(Messages.CLIInterface.tc54f734a37a6.localized)) var optionComponent: [String] = []
    @Flag(name: .customLong("no-install"), help: ArgumentHelp(Messages.CLIInterface.td183fd7d75d0.localized)) var optionNoInstall = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "game": .text(optionGame),
        "directory": .text(optionDirectory),
        "component": .array(optionComponent.map(Value.string)),
        "no-install": .bool(optionNoInstall),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","install"], summary: Messages.CLIInterface.tc5757d580bc3.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRepairCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","repair"], summary: Messages.CLIInterface.te334b8a18014.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceSelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","select"], summary: Messages.CLIInterface.ta4178213b601.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRenameCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","rename"], summary: Messages.CLIInterface.t5ba0c4853561.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tb19f8bbe0060.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceFavoriteCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","favorite"], summary: Messages.CLIInterface.t850a4e6bffbd.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "enabled", type: "string", required: true, help: "enabled")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t07e88e1b19e9.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","remove"], summary: Messages.CLIInterface.t1e047c3f4441.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct InstanceIconCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","icon"], summary: Messages.CLIInterface.t2774fd42ed73.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "file", type: "string", required: false, help: Messages.CLIInterface.tc9dade836bbe.localized, values: []),
        .init(name: "glyph", type: "string", required: false, help: Messages.CLIInterface.t4888fb1eb4ed.localized, values: []),
        .init(name: "tint", type: "string", required: false, help: Messages.CLIInterface.t44893043de60.localized, values: []),
        .init(name: "reset", type: "bool", required: false, help: Messages.CLIInterface.t22cb6cbb2d9e.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.tc9dade836bbe.localized)) var optionFile: String?
    @Option(name: .customLong("glyph"), help: ArgumentHelp(Messages.CLIInterface.t4888fb1eb4ed.localized)) var optionGlyph: String?
    @Option(name: .customLong("tint"), help: ArgumentHelp(Messages.CLIInterface.t44893043de60.localized)) var optionTint: String?
    @Flag(name: .customLong("reset"), help: ArgumentHelp(Messages.CLIInterface.t22cb6cbb2d9e.localized)) var optionReset = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "file": .text(optionFile),
        "glyph": .text(optionGlyph),
        "tint": .text(optionTint),
        "reset": .bool(optionReset),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceCopyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","copy"], summary: Messages.CLIInterface.ta496dc81dcac.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tcba396edfba1.localized, values: []),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.td52e9c9dbb40.localized, values: []),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.t874415ccd0ab.localized, values: []),
        .init(name: "with-backups", type: "bool", required: false, help: Messages.CLIInterface.t4829b4f8f896.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tcba396edfba1.localized)) var optionDirectory: String?
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.td52e9c9dbb40.localized)) var optionName: String?
    @Flag(name: .customLong("without-worlds"), help: ArgumentHelp(Messages.CLIInterface.t874415ccd0ab.localized)) var optionWithoutWorlds = false
    @Flag(name: .customLong("with-backups"), help: ArgumentHelp(Messages.CLIInterface.t4829b4f8f896.localized)) var optionWithBackups = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "name": .text(optionName),
        "without-worlds": .bool(optionWithoutWorlds),
        "with-backups": .bool(optionWithBackups),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceMoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","move"], summary: Messages.CLIInterface.t2aee4e3b9cb2.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tcba396edfba1.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tcba396edfba1.localized)) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","export"], summary: Messages.CLIInterface.t8f4cf0564496.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "format", type: "string", required: false, help: Messages.CLIInterface.t148d4a105bd2.localized, values: ["ruri","complete","multimc","mcbbs","mrpack"]),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.t874415ccd0ab.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tc48ebcacc9f3.localized)) var operands: [String] = []
    @Option(name: .customLong("format"), help: ArgumentHelp(Messages.CLIInterface.t148d4a105bd2.localized)) var optionFormat: String?
    @Flag(name: .customLong("without-worlds"), help: ArgumentHelp(Messages.CLIInterface.t874415ccd0ab.localized)) var optionWithoutWorlds = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "format": .text(optionFormat),
        "without-worlds": .bool(optionWithoutWorlds),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceComponentListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","list"], summary: Messages.CLIInterface.t94761d5853b8.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceComponentVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","versions"], summary: Messages.CLIInterface.t66e7670cbafe.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "loader", type: "string", required: true, help: "loader")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t8ca25fc9cedc.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceComponentSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","set"], summary: Messages.CLIInterface.td7622dae9d70.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.t4465e709e830.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Option(name: .customLong("component"), help: ArgumentHelp(Messages.CLIInterface.t4465e709e830.localized)) var optionComponent: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "component": .array(optionComponent.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceComponentRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","restore"], summary: Messages.CLIInterface.t3d825619ad66.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DirectoryListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","list"], summary: Messages.CLIInterface.tf64fee5acdf0.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DirectorySelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","selected"], summary: Messages.CLIInterface.t13c336f9a11b.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryScanCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","scan"], summary: Messages.CLIInterface.t0a77c8493c2e.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DirectoryAddCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","add"], summary: Messages.CLIInterface.t135973383faa.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.t63c8c08621c5.localized, values: []),
        .init(name: "layout", type: "string", required: false, help: Messages.CLIInterface.t0175170e7603.localized, values: ["minecraft","managed"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.t63c8c08621c5.localized)) var optionName: String?
    @Option(name: .customLong("layout"), help: ArgumentHelp(Messages.CLIInterface.t0175170e7603.localized)) var optionLayout: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "layout": .text(optionLayout),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectorySelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","select"], summary: Messages.CLIInterface.te995381e7764.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRefreshCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","refresh"], summary: Messages.CLIInterface.tac593c150e36.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","remove"], summary: Messages.CLIInterface.t8592d66b70ee.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DirectoryRenameCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","rename"], summary: Messages.CLIInterface.tbbd25ee7fe86.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tb19f8bbe0060.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRelocateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","relocate"], summary: Messages.CLIInterface.t741d898dfaff.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.te5b3e2aa3520.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","restore"], summary: Messages.CLIInterface.teeb75a68ecdc.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.te5b3e2aa3520.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRunGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","get"], summary: Messages.CLIInterface.t72af20234e14.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryRunSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","set"], summary: Messages.CLIInterface.t1db840ce735d.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "mode", type: "string", required: true, help: "mode")
    ], options: [
        .init(name: "path", type: "string", required: false, help: Messages.CLIInterface.t4d6e9b1a4264.localized, values: []),
        .init(name: "copy", type: "bool", required: false, help: Messages.CLIInterface.ta39f0e134724.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tdb3bd307aea7.localized)) var operands: [String] = []
    @Option(name: .customLong("path"), help: ArgumentHelp(Messages.CLIInterface.t4d6e9b1a4264.localized)) var optionPath: String?
    @Flag(name: .customLong("copy"), help: ArgumentHelp(Messages.CLIInterface.ta39f0e134724.localized)) var optionCopy = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "path": .text(optionPath),
        "copy": .bool(optionCopy),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRunRelocateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","relocate"], summary: Messages.CLIInterface.tfe9e723a6df9.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.td41369a235db.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","list"], summary: Messages.CLIInterface.t738bb690d8c2.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaAvailableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","available"], summary: Messages.CLIInterface.t1cd05347cc64.localized, operands: [

    ], options: [
        .init(name: "major", type: "int", required: false, help: Messages.CLIInterface.teba714b1f2cc.localized, values: []),
        .init(name: "architecture", type: "string", required: false, help: Messages.CLIInterface.taa6237af9422.localized, values: ["aarch64","x86_64"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("major"), help: ArgumentHelp(Messages.CLIInterface.teba714b1f2cc.localized)) var optionMajor: Int?
    @Option(name: .customLong("architecture"), help: ArgumentHelp(Messages.CLIInterface.taa6237af9422.localized)) var optionArchitecture: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "major": optionMajor.map(Value.integer) ?? .null,
        "architecture": .text(optionArchitecture),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaAddCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","add"], summary: Messages.CLIInterface.tf3cf2acb7b9a.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaForgetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","forget"], summary: Messages.CLIInterface.t0ecfbec54289.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaDefaultCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","default"], summary: Messages.CLIInterface.tea0c61c73f43.localized, operands: [
        .init(name: "path-or-automatic", type: "string", required: true, help: "path-or-automatic")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "path-or-automatic") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaReferencesCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","references"], summary: Messages.CLIInterface.td99052ac398d.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.tb07678654f81.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("partial"), help: ArgumentHelp(Messages.CLIInterface.tb07678654f81.localized)) var optionPartial = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "partial": .bool(optionPartial),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","install"], summary: Messages.CLIInterface.t2b2ab103144b.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRepairCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","repair"], summary: Messages.CLIInterface.tef883d8efb5c.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","remove"], summary: Messages.CLIInterface.t355d66c16583.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "reset-references", type: "bool", required: false, help: Messages.CLIInterface.t5897a3d49bb5.localized, values: []),
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.t2a5f80694223.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("reset-references"), help: ArgumentHelp(Messages.CLIInterface.t5897a3d49bb5.localized)) var optionResetReferences = false
    @Flag(name: .customLong("partial"), help: ArgumentHelp(Messages.CLIInterface.t2a5f80694223.localized)) var optionPartial = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "reset-references": .bool(optionResetReferences),
        "partial": .bool(optionPartial),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","list"], summary: Messages.CLIInterface.t347c8e743183.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct AccountSelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","selected"], summary: Messages.CLIInterface.t60065624116e.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","show"], summary: Messages.CLIInterface.t29349e23e1f2.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountAddOfflineCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","add-offline"], summary: Messages.CLIInterface.t5e3954fd00e4.localized, operands: [
        .init(name: "username", type: "string", required: true, help: "username")
    ], options: [
        .init(name: "no-select", type: "bool", required: false, help: Messages.CLIInterface.t4fbd66e4df1d.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "username") var operands: [String] = []
    @Flag(name: .customLong("no-select"), help: ArgumentHelp(Messages.CLIInterface.t4fbd66e4df1d.localized)) var optionNoSelect = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "no-select": .bool(optionNoSelect),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountSelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","select"], summary: Messages.CLIInterface.ta88c8f0fa07b.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRefreshCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","refresh"], summary: Messages.CLIInterface.te68622e3a4c1.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","remove"], summary: Messages.CLIInterface.t222e7542a935.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountLogoutCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","logout"], summary: Messages.CLIInterface.t9de45ca5dfe9.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountLoginStartCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","start"], summary: Messages.CLIInterface.t5e3d504d2f33.localized, operands: [

    ], options: [
        .init(name: "provider", type: "string", required: true, help: Messages.CLIInterface.t35f41c8dfeb7.localized, values: ["microsoft","external"]),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.t06b9c339e88c.localized, values: []),
        .init(name: "server", type: "string", required: false, help: Messages.CLIInterface.tda3d5eaa9c6b.localized, values: []),
        .init(name: "username", type: "string", required: false, help: Messages.CLIInterface.t598bd6abd203.localized, values: []),
        .init(name: "password-stdin", type: "bool", required: false, help: Messages.CLIInterface.tae550ce2501b.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: ["ruri account login start --provider microsoft --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.t35f41c8dfeb7.localized)) var optionProvider: String?
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.t06b9c339e88c.localized)) var optionAccount: String?
    @Option(name: .customLong("server"), help: ArgumentHelp(Messages.CLIInterface.tda3d5eaa9c6b.localized)) var optionServer: String?
    @Option(name: .customLong("username"), help: ArgumentHelp(Messages.CLIInterface.t598bd6abd203.localized)) var optionUsername: String?
    @Flag(name: .customLong("password-stdin"), help: ArgumentHelp(Messages.CLIInterface.tae550ce2501b.localized)) var optionPasswordStdin = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "account": .text(optionAccount),
        "server": .text(optionServer),
        "username": .text(optionUsername),
        "password-stdin": .bool(optionPasswordStdin),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountLoginCompleteCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","complete"], summary: Messages.CLIInterface.td905be5334b1.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: "flow")
    ], options: [
        .init(name: "profile", type: "string", required: false, help: Messages.CLIInterface.taa3d1bfbf09d.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "flow") var operands: [String] = []
    @Option(name: .customLong("profile"), help: ArgumentHelp(Messages.CLIInterface.taa3d1bfbf09d.localized)) var optionProfile: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "profile": .text(optionProfile),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountLoginCancelCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","cancel"], summary: Messages.CLIInterface.t7bac79515ad0.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: "flow")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "flow") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","status"], summary: Messages.CLIInterface.t075c8839f62a.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountServiceKeySetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","set"], summary: Messages.CLIInterface.tb513f67f0661.localized, operands: [

    ], options: [
        .init(name: "stdin", type: "bool", required: true, help: Messages.CLIInterface.tbee9e14cb9c8.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Flag(name: .customLong("stdin"), help: ArgumentHelp(Messages.CLIInterface.tbee9e14cb9c8.localized)) var optionStdin = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "stdin": .bool(optionStdin),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","remove"], summary: Messages.CLIInterface.tb412547b5de8.localized, operands: [

    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct LaunchPreflightCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["launch","preflight"], summary: Messages.CLIInterface.tbd6842eb578e.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.tc7d16a18216b.localized, values: []),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.t7650c678063f.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.tc7d16a18216b.localized)) var optionAccount: String?
    @Option(name: .customLong("world"), help: ArgumentHelp(Messages.CLIInterface.t7650c678063f.localized)) var optionWorld: String?
    var parameters: [String: Value] { [
        "account": .text(optionAccount),
        "world": .text(optionWorld)
    ].filter { $0.value != .null } }
}

struct LaunchStartCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["launch","start"], summary: Messages.CLIInterface.tb27f0522d834.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.tc7d16a18216b.localized, values: []),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.t7650c678063f.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri launch start <instance-uuid> --account <account-uuid> --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.tc7d16a18216b.localized)) var optionAccount: String?
    @Option(name: .customLong("world"), help: ArgumentHelp(Messages.CLIInterface.t7650c678063f.localized)) var optionWorld: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "account": .text(optionAccount),
        "world": .text(optionWorld),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SessionListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","list"], summary: Messages.CLIInterface.t75aa2ae95dbf.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.t397da266f14b.localized, values: []),
        .init(name: "search", type: "string", required: false, help: Messages.CLIInterface.t1dc55f419cc4.localized, values: []),
        .init(name: "problems", type: "bool", required: false, help: Messages.CLIInterface.tb23f885979d4.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.t397da266f14b.localized)) var optionInstance: String?
    @Option(name: .customLong("search"), help: ArgumentHelp(Messages.CLIInterface.t1dc55f419cc4.localized)) var optionSearch: String?
    @Flag(name: .customLong("problems"), help: ArgumentHelp(Messages.CLIInterface.tb23f885979d4.localized)) var optionProblems = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "instance": .text(optionInstance),
        "search": .text(optionSearch),
        "problems": .bool(optionProblems),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct SessionShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","show"], summary: Messages.CLIInterface.t1c27c266a051.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionWaitCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","wait"], summary: Messages.CLIInterface.ta977bdb2d5a4.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionQuitCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","quit"], summary: Messages.CLIInterface.t6bbce4221048.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SessionStopCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","stop"], summary: Messages.CLIInterface.t886efc49f631.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct SessionLogsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","logs"], summary: Messages.CLIInterface.t03a5e858530a.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "follow", type: "bool", required: false, help: Messages.CLIInterface.t61dffc7832ee.localized, values: []),
        .init(name: "source", type: "string", required: false, help: Messages.CLIInterface.tdae2c9ca76ca.localized, values: ["output","preparation","latest","debug"]),
        .init(name: "lines", type: "int", required: false, help: Messages.CLIInterface.t602d83ce6e9a.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri session logs <instance-uuid> <session-uuid> --follow --output ndjson"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    @Flag(name: .customLong("follow"), help: ArgumentHelp(Messages.CLIInterface.t61dffc7832ee.localized)) var optionFollow = false
    @Option(name: .customLong("source"), help: ArgumentHelp(Messages.CLIInterface.tdae2c9ca76ca.localized)) var optionSource: String?
    @Option(name: .customLong("lines"), help: ArgumentHelp(Messages.CLIInterface.t602d83ce6e9a.localized)) var optionLines: Int?
    var parameters: [String: Value] { [
        "follow": .bool(optionFollow),
        "source": .text(optionSource),
        "lines": optionLines.map(Value.integer) ?? .null
    ].filter { $0.value != .null } }
}

struct SessionDiagnoseCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","diagnose"], summary: Messages.CLIInterface.t5cf1cb615468.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","export"], summary: Messages.CLIInterface.t33ed51c9688b.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t4e51dca76f06.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CatalogSearchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","search"], summary: Messages.CLIInterface.t9585ae182d36.localized, operands: [
        .init(name: "query", type: "string", required: false, help: "query")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.t54d62b370b12.localized, values: ["modrinth","curseforge"]),
        .init(name: "type", type: "string", required: false, help: Messages.CLIInterface.t9c7c66e1cb97.localized, values: ["mod","modpack","resourcepack","shader"]),
        .init(name: "game", type: "string", required: false, help: Messages.CLIInterface.t97bb290079c0.localized, values: []),
        .init(name: "loader", type: "string", required: false, help: Messages.CLIInterface.t6cd3985335f5.localized, values: []),
        .init(name: "category", type: "string", required: false, help: Messages.CLIInterface.tba245c5c5887.localized, values: []),
        .init(name: "sort", type: "string", required: false, help: Messages.CLIInterface.tffbd359b4372.localized, values: ["relevance","downloads","updated","newest"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "query?") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.t54d62b370b12.localized)) var optionProvider: String?
    @Option(name: .customLong("type"), help: ArgumentHelp(Messages.CLIInterface.t9c7c66e1cb97.localized)) var optionType: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.t97bb290079c0.localized)) var optionGame: String?
    @Option(name: .customLong("loader"), help: ArgumentHelp(Messages.CLIInterface.t6cd3985335f5.localized)) var optionLoader: String?
    @Option(name: .customLong("category"), help: ArgumentHelp(Messages.CLIInterface.tba245c5c5887.localized)) var optionCategory: String?
    @Option(name: .customLong("sort"), help: ArgumentHelp(Messages.CLIInterface.tffbd359b4372.localized)) var optionSort: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "type": .text(optionType),
        "game": .text(optionGame),
        "loader": .text(optionLoader),
        "category": .text(optionCategory),
        "sort": .text(optionSort),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct CatalogShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","show"], summary: Messages.CLIInterface.tef252f7e18ac.localized, operands: [
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.t54d62b370b12.localized, values: ["modrinth","curseforge"])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "project") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.t54d62b370b12.localized)) var optionProvider: String?
    var parameters: [String: Value] { [
        "provider": .text(optionProvider)
    ].filter { $0.value != .null } }
}

struct CatalogVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","versions"], summary: Messages.CLIInterface.t2015ae2ed51d.localized, operands: [
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.t54d62b370b12.localized, values: ["modrinth","curseforge"]),
        .init(name: "game", type: "string", required: false, help: Messages.CLIInterface.t97bb290079c0.localized, values: []),
        .init(name: "loader", type: "string", required: false, help: Messages.CLIInterface.t6cd3985335f5.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "project") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.t54d62b370b12.localized)) var optionProvider: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.t97bb290079c0.localized)) var optionGame: String?
    @Option(name: .customLong("loader"), help: ArgumentHelp(Messages.CLIInterface.t6cd3985335f5.localized)) var optionLoader: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "game": .text(optionGame),
        "loader": .text(optionLoader),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct CatalogCategoriesCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","categories"], summary: Messages.CLIInterface.t96729fb469a0.localized, operands: [

    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.t54d62b370b12.localized, values: ["modrinth","curseforge"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.t54d62b370b12.localized)) var optionProvider: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct ContentListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","list"], summary: Messages.CLIInterface.t31b908b482c0.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.t1615f94ae45c.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.t1615f94ae45c.localized)) var optionKind: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct ContentImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","import"], summary: Messages.CLIInterface.t0adabdb41fc9.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.t1615f94ae45c.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t1221c915a9ab.localized)) var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.t1615f94ae45c.localized)) var optionKind: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","install"], summary: Messages.CLIInterface.t6f5c9d328e9f.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.t54d62b370b12.localized, values: ["modrinth","curseforge"]),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.t3adc46ef11f2.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.t6937c4e2d52d.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri content install <instance-uuid> sodium --provider modrinth --dry-run --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tc9423b403749.localized)) var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.t54d62b370b12.localized)) var optionProvider: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.t3adc46ef11f2.localized)) var optionVersion: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.t6937c4e2d52d.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "version": .text(optionVersion),
        "manual": .array(optionManual.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentEnableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","enable"], summary: Messages.CLIInterface.tcb22bf7cdc22.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.t1615f94ae45c.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.t0571cf34f7e5.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.t7a83bde60a43.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.t1615f94ae45c.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.t0571cf34f7e5.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.t7a83bde60a43.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentDisableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","disable"], summary: Messages.CLIInterface.t835a12065b6b.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.t1615f94ae45c.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.t0571cf34f7e5.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.t7a83bde60a43.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.t1615f94ae45c.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.t0571cf34f7e5.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.t7a83bde60a43.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","remove"], summary: Messages.CLIInterface.tbddc7b97257e.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.t1615f94ae45c.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.t0571cf34f7e5.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.t7a83bde60a43.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.t1615f94ae45c.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.t0571cf34f7e5.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.t7a83bde60a43.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct ContentUpdateCheckCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","update-check"], summary: Messages.CLIInterface.t2648b2127df6.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.t1615f94ae45c.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.t0571cf34f7e5.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.t1615f94ae45c.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.t0571cf34f7e5.localized)) var optionFile: [String] = []
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string))
    ].filter { $0.value != .null } }
}

struct ContentUpdateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","update"], summary: Messages.CLIInterface.t41cfb5271f5e.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.t1615f94ae45c.localized, values: ["mod","resourcepack","shader"]),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.t0571cf34f7e5.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.tf53d1d120842.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.t6937c4e2d52d.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.t1615f94ae45c.localized)) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.t0571cf34f7e5.localized)) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.tf53d1d120842.localized)) var optionAll = false
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.t6937c4e2d52d.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "manual": .array(optionManual.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","list"], summary: Messages.CLIInterface.t0182348543ec.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct WorldShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","show"], summary: Messages.CLIInterface.tc62375cad94f.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t3cc465fee86f.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct WorldImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","import"], summary: Messages.CLIInterface.td02c3799e5f3.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t1221c915a9ab.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","export"], summary: Messages.CLIInterface.t79b53bfe32d0.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tbb4df9d7ac3a.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","remove"], summary: Messages.CLIInterface.t1f3b65ed9678.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t3cc465fee86f.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct WorldBackupCreateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","create"], summary: Messages.CLIInterface.t687aa81ce15b.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "folder", type: "string", required: true, help: "folder")
    ], options: [
        .init(name: "reason", type: "string", required: false, help: Messages.CLIInterface.t243960f924a4.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t3cc465fee86f.localized)) var operands: [String] = []
    @Option(name: .customLong("reason"), help: ArgumentHelp(Messages.CLIInterface.t243960f924a4.localized)) var optionReason: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "reason": .text(optionReason),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldBackupListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","list"], summary: Messages.CLIInterface.t82358ac73619.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct WorldBackupRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","restore"], summary: Messages.CLIInterface.t5b12f1ab5a68.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "backup", type: "string", required: true, help: "backup")
    ], options: [
        .init(name: "replace", type: "bool", required: false, help: Messages.CLIInterface.td2c29dd5d868.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.teaf6d847cc14.localized)) var operands: [String] = []
    @Flag(name: .customLong("replace"), help: ArgumentHelp(Messages.CLIInterface.td2c29dd5d868.localized)) var optionReplace = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "replace": .bool(optionReplace),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct WorldBackupRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","remove"], summary: Messages.CLIInterface.t79d8f9c1b13b.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "backup", type: "string", required: true, help: "backup")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.teaf6d847cc14.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DatapackListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","list"], summary: Messages.CLIInterface.t5baea7450859.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t3f8f11058c17.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackOrderGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","order","get"], summary: Messages.CLIInterface.t8e719af86d09.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t3f8f11058c17.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DatapackOrderSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","order","set"], summary: Messages.CLIInterface.tc4ef4044f6a8.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world")
    ], options: [
        .init(name: "key", type: "strings", required: true, help: Messages.CLIInterface.tcc64529d6ae6.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t3f8f11058c17.localized)) var operands: [String] = []
    @Option(name: .customLong("key"), help: ArgumentHelp(Messages.CLIInterface.tcc64529d6ae6.localized)) var optionKey: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "key": .array(optionKey.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","import"], summary: Messages.CLIInterface.td44435e60acc.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t027258d65380.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackEnableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","enable"], summary: Messages.CLIInterface.t8c443e635faf.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t25b74fe94bbb.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackDisableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","disable"], summary: Messages.CLIInterface.tc7d244ea5a4c.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t25b74fe94bbb.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","remove"], summary: Messages.CLIInterface.t08f738b1e5ca.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t25b74fe94bbb.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DatapackSearchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","search"], summary: Messages.CLIInterface.t64d56130fbdf.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "query", type: "string", required: true, help: "query")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t9abc5f05470e.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","versions"], summary: Messages.CLIInterface.tb511553d589f.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tc9423b403749.localized)) var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","install"], summary: Messages.CLIInterface.t37b2077e3554.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "world", type: "string", required: true, help: "world"),
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.t5e7708f69f60.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t4d5a09c55c8c.localized)) var operands: [String] = []
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.t5e7708f69f60.localized)) var optionVersion: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "version": .text(optionVersion),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","list"], summary: Messages.CLIInterface.t45ce4d2add4d.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.tc48ff6cbe772.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tc48ff6cbe772.localized)) var optionDirectory: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct SchematicInfoCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","info"], summary: Messages.CLIInterface.t9691b8cb26ac.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.td41369a235db.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SchematicImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","import"], summary: Messages.CLIInterface.t006d1cafc637.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.tc48ff6cbe772.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t1221c915a9ab.localized)) var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tc48ff6cbe772.localized)) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicMkdirCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","mkdir"], summary: Messages.CLIInterface.tf32e6e0f57a1.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.t4af5860f6aeb.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t0d2ff8c9a278.localized)) var operands: [String] = []
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.t4af5860f6aeb.localized)) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","export"], summary: Messages.CLIInterface.t7e11030c3d95.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tf0b7b313a90b.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","remove"], summary: Messages.CLIInterface.tc7d49c67a14a.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.td41369a235db.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct InstanceImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","import"], summary: Messages.CLIInterface.tdb74aa2f7d3b.localized, operands: [
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.td52e9c9dbb40.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tddd82092eded.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.t6937c4e2d52d.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.tb86fa4ea53ac.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "file") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.td52e9c9dbb40.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tddd82092eded.localized)) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.t6937c4e2d52d.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.tb86fa4ea53ac.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","import"], summary: Messages.CLIInterface.tc5c676ace213.localized, operands: [
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.td52e9c9dbb40.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tddd82092eded.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.t6937c4e2d52d.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.tb86fa4ea53ac.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "file") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.td52e9c9dbb40.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tddd82092eded.localized)) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.t6937c4e2d52d.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.tb86fa4ea53ac.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","install"], summary: Messages.CLIInterface.td48597adbed9.localized, operands: [
        .init(name: "project", type: "string", required: true, help: "project")
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.t54d62b370b12.localized, values: ["modrinth","curseforge"]),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.t3adc46ef11f2.localized, values: []),
        .init(name: "archive", type: "string", required: false, help: Messages.CLIInterface.t2280d783f7cb.localized, values: []),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.td52e9c9dbb40.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tddd82092eded.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.t6937c4e2d52d.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.tb86fa4ea53ac.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "project") var operands: [String] = []
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.t54d62b370b12.localized)) var optionProvider: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.t3adc46ef11f2.localized)) var optionVersion: String?
    @Option(name: .customLong("archive"), help: ArgumentHelp(Messages.CLIInterface.t2280d783f7cb.localized)) var optionArchive: String?
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.td52e9c9dbb40.localized)) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.tddd82092eded.localized)) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.t6937c4e2d52d.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.tb86fa4ea53ac.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "version": .text(optionVersion),
        "archive": .text(optionArchive),
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","show"], summary: Messages.CLIInterface.t1d9fc0c70e58.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct PackUpdateCheckCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","update-check"], summary: Messages.CLIInterface.t0e0ee827fcda.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct PackUpdateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","update"], summary: Messages.CLIInterface.t7dd4704843e2.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "file", type: "string", required: false, help: Messages.CLIInterface.te3ce5542c760.localized, values: []),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.tadff65d82cd8.localized, values: []),
        .init(name: "archive", type: "string", required: false, help: Messages.CLIInterface.t33673a17c78a.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.t6937c4e2d52d.localized, values: []),
        .init(name: "replace", type: "bool", required: false, help: Messages.CLIInterface.tfa5924a2e888.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.tf986137b0dee.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.tb86fa4ea53ac.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.te3ce5542c760.localized)) var optionFile: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.tadff65d82cd8.localized)) var optionVersion: String?
    @Option(name: .customLong("archive"), help: ArgumentHelp(Messages.CLIInterface.t33673a17c78a.localized)) var optionArchive: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.t6937c4e2d52d.localized)) var optionManual: [String] = []
    @Flag(name: .customLong("replace"), help: ArgumentHelp(Messages.CLIInterface.tfa5924a2e888.localized)) var optionReplace = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.tf986137b0dee.localized)) var optionYes = false
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.tb86fa4ea53ac.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "file": .text(optionFile),
        "version": .text(optionVersion),
        "archive": .text(optionArchive),
        "manual": .array(optionManual.map(Value.string)),
        "replace": .bool(optionReplace),
        "yes": .bool(optionYes),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackRollbackCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","rollback"], summary: Messages.CLIInterface.t8951a110d64d.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DownloadFetchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["download","fetch"], summary: Messages.CLIInterface.t869f83eac4a5.localized, operands: [
        .init(name: "url", type: "string", required: true, help: "url"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "sha1", type: "string", required: true, help: Messages.CLIInterface.t91bde8e5fa30.localized, values: []),
        .init(name: "size", type: "int", required: true, help: Messages.CLIInterface.t8e1d27b3966c.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tff2b9d62fa33.localized)) var operands: [String] = []
    @Option(name: .customLong("sha1"), help: ArgumentHelp(Messages.CLIInterface.t91bde8e5fa30.localized)) var optionSha1: String?
    @Option(name: .customLong("size"), help: ArgumentHelp(Messages.CLIInterface.t8e1d27b3966c.localized)) var optionSize: Int?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "sha1": .text(optionSha1),
        "size": optionSize.map(Value.integer) ?? .null,
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct RecoveryListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["recovery","list"], summary: Messages.CLIInterface.tbff4f0f5e780.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.tc16fc65ec610.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.tc16fc65ec610.localized)) var optionInstance: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.te46ca00ec899.localized)) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.t184bd8d0fe9d.localized)) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.ta412189d9e76.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "instance": .text(optionInstance),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct RecoveryApplyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["recovery","apply"], summary: Messages.CLIInterface.t25597cca30a1.localized, operands: [
        .init(name: "kind", type: "string", required: true, help: "kind"),
        .init(name: "target", type: "string", required: true, help: "target")
    ], options: [
        .init(name: "transaction", type: "string", required: false, help: Messages.CLIInterface.t617ad9bacfae.localized, values: []),
        .init(name: "mode", type: "string", required: false, help: Messages.CLIInterface.ta51e4f921383.localized, values: ["finish","keep-files"]),
        .init(name: "keep-source", type: "bool", required: false, help: Messages.CLIInterface.t709f4fc13c7d.localized, values: []),
        .init(name: "confirm-game-ended", type: "bool", required: false, help: Messages.CLIInterface.ta42e19194027.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t28237d41435e.localized)) var operands: [String] = []
    @Option(name: .customLong("transaction"), help: ArgumentHelp(Messages.CLIInterface.t617ad9bacfae.localized)) var optionTransaction: String?
    @Option(name: .customLong("mode"), help: ArgumentHelp(Messages.CLIInterface.ta51e4f921383.localized)) var optionMode: String?
    @Flag(name: .customLong("keep-source"), help: ArgumentHelp(Messages.CLIInterface.t709f4fc13c7d.localized)) var optionKeepSource = false
    @Flag(name: .customLong("confirm-game-ended"), help: ArgumentHelp(Messages.CLIInterface.ta42e19194027.localized)) var optionConfirmGameEnded = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.t3b0368de0fdf.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "transaction": .text(optionTransaction),
        "mode": .text(optionMode),
        "keep-source": .bool(optionKeepSource),
        "confirm-game-ended": .bool(optionConfirmGameEnded),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DoctorCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["doctor"], summary: Messages.CLIInterface.tc168cea3e30b.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.tcfab76824678.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.tcfab76824678.localized)) var optionInstance: String?
    var parameters: [String: Value] { [
        "instance": .text(optionInstance)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "service-key", abstract: Messages.CLIInterface.td9b80535359b.localized, subcommands: [AccountServiceKeyStatusCommand.self, AccountServiceKeySetCommand.self, AccountServiceKeyRemoveCommand.self]) }
}

struct InstanceComponentGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "component", abstract: Messages.CLIInterface.t336d8b6931f5.localized, subcommands: [InstanceComponentListCommand.self, InstanceComponentVersionsCommand.self, InstanceComponentSetCommand.self, InstanceComponentRestoreCommand.self]) }
}

struct DatapackOrderGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "order", abstract: Messages.CLIInterface.tb9f8304a17cd.localized, subcommands: [DatapackOrderGetCommand.self, DatapackOrderSetCommand.self]) }
}

struct DirectoryRunGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "run", abstract: Messages.CLIInterface.tc67f25bb4cc3.localized, subcommands: [DirectoryRunGetCommand.self, DirectoryRunSetCommand.self, DirectoryRunRelocateCommand.self]) }
}

struct AccountLoginGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "login", abstract: Messages.CLIInterface.t463334485f56.localized, subcommands: [AccountLoginStartCommand.self, AccountLoginCompleteCommand.self, AccountLoginCancelCommand.self]) }
}

struct AppLanguageGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "language", abstract: Messages.CLIInterface.teaca59ff6999.localized, subcommands: [AppLanguageGetCommand.self, AppLanguageSetCommand.self]) }
}

struct WorldBackupGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "backup", abstract: Messages.CLIInterface.t1870161676bc.localized, subcommands: [WorldBackupCreateCommand.self, WorldBackupListCommand.self, WorldBackupRestoreCommand.self, WorldBackupRemoveCommand.self]) }
}

struct DirectoryGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "directory", abstract: Messages.CLIInterface.ta42145487540.localized, subcommands: [DirectoryListCommand.self, DirectorySelectedCommand.self, DirectoryScanCommand.self, DirectoryAddCommand.self, DirectorySelectCommand.self, DirectoryRefreshCommand.self, DirectoryRemoveCommand.self, DirectoryRenameCommand.self, DirectoryRelocateCommand.self, DirectoryRestoreCommand.self, DirectoryRunGroup.self]) }
}

struct SchematicGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "schematic", abstract: Messages.CLIInterface.tb977dca13b5f.localized, subcommands: [SchematicListCommand.self, SchematicInfoCommand.self, SchematicImportCommand.self, SchematicMkdirCommand.self, SchematicExportCommand.self, SchematicRemoveCommand.self]) }
}

struct InstanceGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "instance", abstract: Messages.CLIInterface.tea19eba1f497.localized, subcommands: [InstanceListCommand.self, InstanceSelectedCommand.self, InstanceShowCommand.self, InstanceVersionsCommand.self, InstanceCreateCommand.self, InstanceInstallCommand.self, InstanceRepairCommand.self, InstanceSelectCommand.self, InstanceRenameCommand.self, InstanceFavoriteCommand.self, InstanceRemoveCommand.self, InstanceIconCommand.self, InstanceCopyCommand.self, InstanceMoveCommand.self, InstanceExportCommand.self, InstanceComponentGroup.self, InstanceImportCommand.self]) }
}

struct DatapackGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "datapack", abstract: Messages.CLIInterface.t8c1e16e1c7f6.localized, subcommands: [DatapackListCommand.self, DatapackOrderGroup.self, DatapackImportCommand.self, DatapackEnableCommand.self, DatapackDisableCommand.self, DatapackRemoveCommand.self, DatapackSearchCommand.self, DatapackVersionsCommand.self, DatapackInstallCommand.self]) }
}

struct DownloadGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "download", abstract: Messages.CLIInterface.ta16b7c00b2ba.localized, subcommands: [DownloadFetchCommand.self]) }
}

struct RecoveryGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "recovery", abstract: Messages.CLIInterface.t2b167c0c4363.localized, subcommands: [RecoveryListCommand.self, RecoveryApplyCommand.self]) }
}

struct AccountGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "account", abstract: Messages.CLIInterface.t52f4179738c0.localized, subcommands: [AccountListCommand.self, AccountSelectedCommand.self, AccountShowCommand.self, AccountAddOfflineCommand.self, AccountSelectCommand.self, AccountRefreshCommand.self, AccountRemoveCommand.self, AccountLogoutCommand.self, AccountLoginGroup.self, AccountServiceKeyGroup.self]) }
}

struct SessionGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "session", abstract: Messages.CLIInterface.t03b417601a2c.localized, subcommands: [SessionListCommand.self, SessionShowCommand.self, SessionWaitCommand.self, SessionQuitCommand.self, SessionStopCommand.self, SessionLogsCommand.self, SessionDiagnoseCommand.self, SessionExportCommand.self]) }
}

struct CatalogGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "catalog", abstract: Messages.CLIInterface.t28a32d5bd18e.localized, subcommands: [CatalogSearchCommand.self, CatalogShowCommand.self, CatalogVersionsCommand.self, CatalogCategoriesCommand.self]) }
}

struct ContentGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "content", abstract: Messages.CLIInterface.t7f93a6deea4d.localized, subcommands: [ContentListCommand.self, ContentImportCommand.self, ContentInstallCommand.self, ContentEnableCommand.self, ContentDisableCommand.self, ContentRemoveCommand.self, ContentUpdateCheckCommand.self, ContentUpdateCommand.self]) }
}

struct ConfigGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "config", abstract: Messages.CLIInterface.t1fcd3e7a6ffc.localized, subcommands: [ConfigGetCommand.self, ConfigSetCommand.self, ConfigApplyCommand.self, ConfigResetCommand.self, ConfigInheritCommand.self]) }
}

struct LaunchGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "launch", abstract: Messages.CLIInterface.t91806a3a3cd3.localized, subcommands: [LaunchPreflightCommand.self, LaunchStartCommand.self]) }
}

struct WorldGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "world", abstract: Messages.CLIInterface.tc96234263475.localized, subcommands: [WorldListCommand.self, WorldShowCommand.self, WorldImportCommand.self, WorldExportCommand.self, WorldRemoveCommand.self, WorldBackupGroup.self]) }
}

struct JavaGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "java", abstract: Messages.CLIInterface.tcb439480ed22.localized, subcommands: [JavaListCommand.self, JavaAvailableCommand.self, JavaAddCommand.self, JavaForgetCommand.self, JavaDefaultCommand.self, JavaReferencesCommand.self, JavaInstallCommand.self, JavaRepairCommand.self, JavaRemoveCommand.self]) }
}

struct PackGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "pack", abstract: Messages.CLIInterface.t31f0b68ea764.localized, subcommands: [PackImportCommand.self, PackInstallCommand.self, PackShowCommand.self, PackUpdateCheckCommand.self, PackUpdateCommand.self, PackRollbackCommand.self]) }
}

struct AppGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "app", abstract: Messages.CLIInterface.t64c4a55a8346.localized, subcommands: [AppInfoCommand.self, AppLanguageGroup.self]) }
}

struct CliGroup: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "cli", abstract: Messages.CLIInterface.td9fc3f8ff28d.localized, subcommands: [CliStatusCommand.self, CliInstallCommand.self, CliUninstallCommand.self]) }
}

struct RuriCommand: ParsableCommand {
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "ruri", abstract: Messages.CLIInterface.ta03f160849e6.localized, version: BuildConfiguration().version, subcommands: [SchemaCommand.self, AppGroup.self, CliGroup.self, ConfigGroup.self, InstanceGroup.self, DirectoryGroup.self, JavaGroup.self, AccountGroup.self, LaunchGroup.self, SessionGroup.self, CatalogGroup.self, ContentGroup.self, WorldGroup.self, DatapackGroup.self, SchematicGroup.self, PackGroup.self, DownloadGroup.self, RecoveryGroup.self, DoctorCommand.self]) }
}

enum CommandRegistry {
    static var commands: [CommandSpec] { [SchemaCommand.spec, AppInfoCommand.spec, AppLanguageGetCommand.spec, AppLanguageSetCommand.spec, CliStatusCommand.spec, CliInstallCommand.spec, CliUninstallCommand.spec, ConfigGetCommand.spec, ConfigSetCommand.spec, ConfigApplyCommand.spec, ConfigResetCommand.spec, ConfigInheritCommand.spec, InstanceListCommand.spec, InstanceSelectedCommand.spec, InstanceShowCommand.spec, InstanceVersionsCommand.spec, InstanceCreateCommand.spec, InstanceInstallCommand.spec, InstanceRepairCommand.spec, InstanceSelectCommand.spec, InstanceRenameCommand.spec, InstanceFavoriteCommand.spec, InstanceRemoveCommand.spec, InstanceIconCommand.spec, InstanceCopyCommand.spec, InstanceMoveCommand.spec, InstanceExportCommand.spec, InstanceComponentListCommand.spec, InstanceComponentVersionsCommand.spec, InstanceComponentSetCommand.spec, InstanceComponentRestoreCommand.spec, DirectoryListCommand.spec, DirectorySelectedCommand.spec, DirectoryScanCommand.spec, DirectoryAddCommand.spec, DirectorySelectCommand.spec, DirectoryRefreshCommand.spec, DirectoryRemoveCommand.spec, DirectoryRenameCommand.spec, DirectoryRelocateCommand.spec, DirectoryRestoreCommand.spec, DirectoryRunGetCommand.spec, DirectoryRunSetCommand.spec, DirectoryRunRelocateCommand.spec, JavaListCommand.spec, JavaAvailableCommand.spec, JavaAddCommand.spec, JavaForgetCommand.spec, JavaDefaultCommand.spec, JavaReferencesCommand.spec, JavaInstallCommand.spec, JavaRepairCommand.spec, JavaRemoveCommand.spec, AccountListCommand.spec, AccountSelectedCommand.spec, AccountShowCommand.spec, AccountAddOfflineCommand.spec, AccountSelectCommand.spec, AccountRefreshCommand.spec, AccountRemoveCommand.spec, AccountLogoutCommand.spec, AccountLoginStartCommand.spec, AccountLoginCompleteCommand.spec, AccountLoginCancelCommand.spec, AccountServiceKeyStatusCommand.spec, AccountServiceKeySetCommand.spec, AccountServiceKeyRemoveCommand.spec, LaunchPreflightCommand.spec, LaunchStartCommand.spec, SessionListCommand.spec, SessionShowCommand.spec, SessionWaitCommand.spec, SessionQuitCommand.spec, SessionStopCommand.spec, SessionLogsCommand.spec, SessionDiagnoseCommand.spec, SessionExportCommand.spec, CatalogSearchCommand.spec, CatalogShowCommand.spec, CatalogVersionsCommand.spec, CatalogCategoriesCommand.spec, ContentListCommand.spec, ContentImportCommand.spec, ContentInstallCommand.spec, ContentEnableCommand.spec, ContentDisableCommand.spec, ContentRemoveCommand.spec, ContentUpdateCheckCommand.spec, ContentUpdateCommand.spec, WorldListCommand.spec, WorldShowCommand.spec, WorldImportCommand.spec, WorldExportCommand.spec, WorldRemoveCommand.spec, WorldBackupCreateCommand.spec, WorldBackupListCommand.spec, WorldBackupRestoreCommand.spec, WorldBackupRemoveCommand.spec, DatapackListCommand.spec, DatapackOrderGetCommand.spec, DatapackOrderSetCommand.spec, DatapackImportCommand.spec, DatapackEnableCommand.spec, DatapackDisableCommand.spec, DatapackRemoveCommand.spec, DatapackSearchCommand.spec, DatapackVersionsCommand.spec, DatapackInstallCommand.spec, SchematicListCommand.spec, SchematicInfoCommand.spec, SchematicImportCommand.spec, SchematicMkdirCommand.spec, SchematicExportCommand.spec, SchematicRemoveCommand.spec, InstanceImportCommand.spec, PackImportCommand.spec, PackInstallCommand.spec, PackShowCommand.spec, PackUpdateCheckCommand.spec, PackUpdateCommand.spec, PackRollbackCommand.spec, DownloadFetchCommand.spec, RecoveryListCommand.spec, RecoveryApplyCommand.spec, DoctorCommand.spec] }
}

