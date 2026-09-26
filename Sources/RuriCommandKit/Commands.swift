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

struct InstanceListCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","list"], summary: Messages.CLIInterface.t163f689a3d2f.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.t61c2b6ad309c.localized, values: []),
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.t3a0b2a4eac30.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","selected"], summary: Messages.CLIInterface.t1a9316dc0247.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceShowCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","show"], summary: Messages.CLIInterface.td25fbbc9aa83.localized, operands: [
        .init(name: "id", type: "string", required: false, help: "id")
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.t554bb290d490.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id?") var operands: [String] = []
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.t554bb290d490.localized)) var optionName: String?
    var parameters: [String: Value] { [
        "name": .text(optionName)
    ].filter { $0.value != .null } }
}

struct InstanceVersionsCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","versions"], summary: Messages.CLIInterface.t309b2060e6e7.localized, operands: [

    ], options: [
        .init(name: "snapshots", type: "bool", required: false, help: Messages.CLIInterface.t0f6dcda14ae4.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","create"], summary: Messages.CLIInterface.tea647925f201.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.tf78b43b0ee95.localized, values: []),
        .init(name: "game", type: "string", required: true, help: Messages.CLIInterface.tc32a76745397.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tcba396edfba1.localized, values: []),
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.tc54f734a37a6.localized, values: []),
        .init(name: "no-install", type: "bool", required: false, help: Messages.CLIInterface.td183fd7d75d0.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","install"], summary: Messages.CLIInterface.tc5757d580bc3.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRepairCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","repair"], summary: Messages.CLIInterface.te334b8a18014.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceSelectCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","select"], summary: Messages.CLIInterface.ta4178213b601.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRenameCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","rename"], summary: Messages.CLIInterface.t5ba0c4853561.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tb19f8bbe0060.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceFavoriteCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","favorite"], summary: Messages.CLIInterface.t850a4e6bffbd.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "enabled", type: "string", required: true, help: "enabled")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t07e88e1b19e9.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRemoveCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","remove"], summary: Messages.CLIInterface.t1e047c3f4441.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","icon"], summary: Messages.CLIInterface.t2774fd42ed73.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "file", type: "string", required: false, help: Messages.CLIInterface.tc9dade836bbe.localized, values: []),
        .init(name: "glyph", type: "string", required: false, help: Messages.CLIInterface.t4888fb1eb4ed.localized, values: []),
        .init(name: "tint", type: "string", required: false, help: Messages.CLIInterface.t44893043de60.localized, values: []),
        .init(name: "reset", type: "bool", required: false, help: Messages.CLIInterface.t22cb6cbb2d9e.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","copy"], summary: Messages.CLIInterface.ta496dc81dcac.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tcba396edfba1.localized, values: []),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.td52e9c9dbb40.localized, values: []),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.t874415ccd0ab.localized, values: []),
        .init(name: "with-backups", type: "bool", required: false, help: Messages.CLIInterface.t4829b4f8f896.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","move"], summary: Messages.CLIInterface.t2aee4e3b9cb2.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.tcba396edfba1.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","export"], summary: Messages.CLIInterface.t8f4cf0564496.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "format", type: "string", required: false, help: Messages.CLIInterface.t148d4a105bd2.localized, values: ["ruri","complete","multimc","mcbbs","mrpack"]),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.t874415ccd0ab.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","component","list"], summary: Messages.CLIInterface.t94761d5853b8.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceComponentVersionsCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["instance","component","versions"], summary: Messages.CLIInterface.t66e7670cbafe.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "loader", type: "string", required: true, help: "loader")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","component","set"], summary: Messages.CLIInterface.td7622dae9d70.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.t4465e709e830.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["instance","component","restore"], summary: Messages.CLIInterface.t3d825619ad66.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["directory","list"], summary: Messages.CLIInterface.tf64fee5acdf0.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["directory","selected"], summary: Messages.CLIInterface.t13c336f9a11b.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryScanCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["directory","scan"], summary: Messages.CLIInterface.t0a77c8493c2e.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["directory","add"], summary: Messages.CLIInterface.t135973383faa.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.t63c8c08621c5.localized, values: []),
        .init(name: "layout", type: "string", required: false, help: Messages.CLIInterface.t0175170e7603.localized, values: ["minecraft","managed"]),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["directory","select"], summary: Messages.CLIInterface.te995381e7764.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRefreshCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["directory","refresh"], summary: Messages.CLIInterface.tac593c150e36.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRemoveCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["directory","remove"], summary: Messages.CLIInterface.t8592d66b70ee.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["directory","rename"], summary: Messages.CLIInterface.tbbd25ee7fe86.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "name", type: "string", required: true, help: "name")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.tb19f8bbe0060.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRelocateCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["directory","relocate"], summary: Messages.CLIInterface.t741d898dfaff.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.te5b3e2aa3520.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRestoreCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["directory","restore"], summary: Messages.CLIInterface.teeb75a68ecdc.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.te5b3e2aa3520.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRunGetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["directory","run","get"], summary: Messages.CLIInterface.t72af20234e14.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "instance") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryRunSetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["directory","run","set"], summary: Messages.CLIInterface.t1db840ce735d.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "mode", type: "string", required: true, help: "mode")
    ], options: [
        .init(name: "path", type: "string", required: false, help: Messages.CLIInterface.t4d6e9b1a4264.localized, values: []),
        .init(name: "copy", type: "bool", required: false, help: Messages.CLIInterface.ta39f0e134724.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["directory","run","relocate"], summary: Messages.CLIInterface.tfe9e723a6df9.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.td41369a235db.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaListCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["java","list"], summary: Messages.CLIInterface.t738bb690d8c2.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["java","available"], summary: Messages.CLIInterface.t1cd05347cc64.localized, operands: [

    ], options: [
        .init(name: "major", type: "int", required: false, help: Messages.CLIInterface.teba714b1f2cc.localized, values: []),
        .init(name: "architecture", type: "string", required: false, help: Messages.CLIInterface.taa6237af9422.localized, values: ["aarch64","x86_64"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["java","add"], summary: Messages.CLIInterface.tf3cf2acb7b9a.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaForgetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["java","forget"], summary: Messages.CLIInterface.t0ecfbec54289.localized, operands: [
        .init(name: "path", type: "string", required: true, help: "path")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "path") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaDefaultCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["java","default"], summary: Messages.CLIInterface.tea0c61c73f43.localized, operands: [
        .init(name: "path-or-automatic", type: "string", required: true, help: "path-or-automatic")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "path-or-automatic") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaReferencesCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["java","references"], summary: Messages.CLIInterface.td99052ac398d.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.tb07678654f81.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["java","install"], summary: Messages.CLIInterface.t2b2ab103144b.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRepairCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["java","repair"], summary: Messages.CLIInterface.tef883d8efb5c.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRemoveCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["java","remove"], summary: Messages.CLIInterface.t355d66c16583.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "reset-references", type: "bool", required: false, help: Messages.CLIInterface.t5897a3d49bb5.localized, values: []),
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.t2a5f80694223.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["account","list"], summary: Messages.CLIInterface.t347c8e743183.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["account","selected"], summary: Messages.CLIInterface.t60065624116e.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountShowCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["account","show"], summary: Messages.CLIInterface.t29349e23e1f2.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountAddOfflineCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["account","add-offline"], summary: Messages.CLIInterface.t5e3954fd00e4.localized, operands: [
        .init(name: "username", type: "string", required: true, help: "username")
    ], options: [
        .init(name: "no-select", type: "bool", required: false, help: Messages.CLIInterface.t4fbd66e4df1d.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["account","select"], summary: Messages.CLIInterface.ta88c8f0fa07b.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRefreshCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["account","refresh"], summary: Messages.CLIInterface.te68622e3a4c1.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "id") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRemoveCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["account","remove"], summary: Messages.CLIInterface.t222e7542a935.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["account","logout"], summary: Messages.CLIInterface.t9de45ca5dfe9.localized, operands: [
        .init(name: "id", type: "string", required: true, help: "id")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["account","login","start"], summary: Messages.CLIInterface.t5e3d504d2f33.localized, operands: [

    ], options: [
        .init(name: "provider", type: "string", required: true, help: Messages.CLIInterface.t35f41c8dfeb7.localized, values: ["microsoft","external"]),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.t06b9c339e88c.localized, values: []),
        .init(name: "server", type: "string", required: false, help: Messages.CLIInterface.tda3d5eaa9c6b.localized, values: []),
        .init(name: "username", type: "string", required: false, help: Messages.CLIInterface.t598bd6abd203.localized, values: []),
        .init(name: "password-stdin", type: "bool", required: false, help: Messages.CLIInterface.tae550ce2501b.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: [])
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
    static let spec = CommandSpec(path: ["account","login","complete"], summary: Messages.CLIInterface.td905be5334b1.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: "flow")
    ], options: [
        .init(name: "profile", type: "string", required: false, help: Messages.CLIInterface.taa3d1bfbf09d.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: [])
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
    static let spec = CommandSpec(path: ["account","login","cancel"], summary: Messages.CLIInterface.t7bac79515ad0.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: "flow")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "flow") var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyStatusCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["account","service-key","status"], summary: Messages.CLIInterface.t075c8839f62a.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: "") var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountServiceKeySetCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["account","service-key","set"], summary: Messages.CLIInterface.tb513f67f0661.localized, operands: [

    ], options: [
        .init(name: "stdin", type: "bool", required: true, help: Messages.CLIInterface.tbee9e14cb9c8.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["account","service-key","remove"], summary: Messages.CLIInterface.tb412547b5de8.localized, operands: [

    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["launch","preflight"], summary: Messages.CLIInterface.tbd6842eb578e.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.tc7d16a18216b.localized, values: []),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.t7650c678063f.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["launch","start"], summary: Messages.CLIInterface.tb27f0522d834.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance")
    ], options: [
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.tc7d16a18216b.localized, values: []),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.t7650c678063f.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["session","list"], summary: Messages.CLIInterface.t75aa2ae95dbf.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.t397da266f14b.localized, values: []),
        .init(name: "search", type: "string", required: false, help: Messages.CLIInterface.t1dc55f419cc4.localized, values: []),
        .init(name: "problems", type: "bool", required: false, help: Messages.CLIInterface.tb23f885979d4.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.te46ca00ec899.localized, values: []),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.t184bd8d0fe9d.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.ta412189d9e76.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["session","show"], summary: Messages.CLIInterface.t1c27c266a051.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionWaitCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["session","wait"], summary: Messages.CLIInterface.ta977bdb2d5a4.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionQuitCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["session","quit"], summary: Messages.CLIInterface.t6bbce4221048.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SessionStopCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["session","stop"], summary: Messages.CLIInterface.t886efc49f631.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.t3b0368de0fdf.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["session","logs"], summary: Messages.CLIInterface.t03a5e858530a.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [
        .init(name: "follow", type: "bool", required: false, help: Messages.CLIInterface.t61dffc7832ee.localized, values: []),
        .init(name: "source", type: "string", required: false, help: Messages.CLIInterface.tdae2c9ca76ca.localized, values: ["output","preparation","latest","debug"]),
        .init(name: "lines", type: "int", required: false, help: Messages.CLIInterface.t602d83ce6e9a.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
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
    static let spec = CommandSpec(path: ["session","diagnose"], summary: Messages.CLIInterface.t5cf1cb615468.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session")
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t7de41631eebc.localized)) var operands: [String] = []
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionExportCommand: ExecutableCommand {
    static let spec = CommandSpec(path: ["session","export"], summary: Messages.CLIInterface.t33ed51c9688b.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: "instance"),
        .init(name: "session", type: "string", required: true, help: "session"),
        .init(name: "file", type: "string", required: true, help: "file")
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.t6034a698016d.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: [])
    @OptionGroup var common: CommonOptions
    @Argument(help: ArgumentHelp(Messages.CLIInterface.t4e51dca76f06.localized)) var operands: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.t6034a698016d.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "service-key", abstract: Messages.CLIInterface.td9b80535359b.localized, subcommands: [AccountServiceKeyStatusCommand.self, AccountServiceKeySetCommand.self, AccountServiceKeyRemoveCommand.self])
}

struct InstanceComponentGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "component", abstract: Messages.CLIInterface.t336d8b6931f5.localized, subcommands: [InstanceComponentListCommand.self, InstanceComponentVersionsCommand.self, InstanceComponentSetCommand.self, InstanceComponentRestoreCommand.self])
}

struct DirectoryRunGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "run", abstract: Messages.CLIInterface.tc67f25bb4cc3.localized, subcommands: [DirectoryRunGetCommand.self, DirectoryRunSetCommand.self, DirectoryRunRelocateCommand.self])
}

struct AccountLoginGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "login", abstract: Messages.CLIInterface.t463334485f56.localized, subcommands: [AccountLoginStartCommand.self, AccountLoginCompleteCommand.self, AccountLoginCancelCommand.self])
}

struct AppLanguageGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "language", abstract: Messages.CLIInterface.teaca59ff6999.localized, subcommands: [AppLanguageGetCommand.self, AppLanguageSetCommand.self])
}

struct DirectoryGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "directory", abstract: Messages.CLIInterface.ta42145487540.localized, subcommands: [DirectoryListCommand.self, DirectorySelectedCommand.self, DirectoryScanCommand.self, DirectoryAddCommand.self, DirectorySelectCommand.self, DirectoryRefreshCommand.self, DirectoryRemoveCommand.self, DirectoryRenameCommand.self, DirectoryRelocateCommand.self, DirectoryRestoreCommand.self, DirectoryRunGroup.self])
}

struct InstanceGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "instance", abstract: Messages.CLIInterface.tea19eba1f497.localized, subcommands: [InstanceListCommand.self, InstanceSelectedCommand.self, InstanceShowCommand.self, InstanceVersionsCommand.self, InstanceCreateCommand.self, InstanceInstallCommand.self, InstanceRepairCommand.self, InstanceSelectCommand.self, InstanceRenameCommand.self, InstanceFavoriteCommand.self, InstanceRemoveCommand.self, InstanceIconCommand.self, InstanceCopyCommand.self, InstanceMoveCommand.self, InstanceExportCommand.self, InstanceComponentGroup.self])
}

struct AccountGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "account", abstract: Messages.CLIInterface.t52f4179738c0.localized, subcommands: [AccountListCommand.self, AccountSelectedCommand.self, AccountShowCommand.self, AccountAddOfflineCommand.self, AccountSelectCommand.self, AccountRefreshCommand.self, AccountRemoveCommand.self, AccountLogoutCommand.self, AccountLoginGroup.self, AccountServiceKeyGroup.self])
}

struct SessionGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "session", abstract: Messages.CLIInterface.t03b417601a2c.localized, subcommands: [SessionListCommand.self, SessionShowCommand.self, SessionWaitCommand.self, SessionQuitCommand.self, SessionStopCommand.self, SessionLogsCommand.self, SessionDiagnoseCommand.self, SessionExportCommand.self])
}

struct ConfigGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "config", abstract: Messages.CLIInterface.t1fcd3e7a6ffc.localized, subcommands: [ConfigGetCommand.self, ConfigSetCommand.self, ConfigApplyCommand.self, ConfigResetCommand.self, ConfigInheritCommand.self])
}

struct LaunchGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "launch", abstract: Messages.CLIInterface.t91806a3a3cd3.localized, subcommands: [LaunchPreflightCommand.self, LaunchStartCommand.self])
}

struct JavaGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "java", abstract: Messages.CLIInterface.tcb439480ed22.localized, subcommands: [JavaListCommand.self, JavaAvailableCommand.self, JavaAddCommand.self, JavaForgetCommand.self, JavaDefaultCommand.self, JavaReferencesCommand.self, JavaInstallCommand.self, JavaRepairCommand.self, JavaRemoveCommand.self])
}

struct AppGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "app", abstract: Messages.CLIInterface.t64c4a55a8346.localized, subcommands: [AppInfoCommand.self, AppLanguageGroup.self])
}

struct CliGroup: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "cli", abstract: Messages.CLIInterface.td9fc3f8ff28d.localized, subcommands: [CliStatusCommand.self, CliInstallCommand.self, CliUninstallCommand.self])
}

struct RuriCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ruri", abstract: Messages.CLIInterface.ta03f160849e6.localized, version: BuildConfiguration().version, subcommands: [SchemaCommand.self, AppGroup.self, CliGroup.self, ConfigGroup.self, InstanceGroup.self, DirectoryGroup.self, JavaGroup.self, AccountGroup.self, LaunchGroup.self, SessionGroup.self])
}

enum CommandRegistry {
    static let commands: [CommandSpec] = [SchemaCommand.spec, AppInfoCommand.spec, AppLanguageGetCommand.spec, AppLanguageSetCommand.spec, CliStatusCommand.spec, CliInstallCommand.spec, CliUninstallCommand.spec, ConfigGetCommand.spec, ConfigSetCommand.spec, ConfigApplyCommand.spec, ConfigResetCommand.spec, ConfigInheritCommand.spec, InstanceListCommand.spec, InstanceSelectedCommand.spec, InstanceShowCommand.spec, InstanceVersionsCommand.spec, InstanceCreateCommand.spec, InstanceInstallCommand.spec, InstanceRepairCommand.spec, InstanceSelectCommand.spec, InstanceRenameCommand.spec, InstanceFavoriteCommand.spec, InstanceRemoveCommand.spec, InstanceIconCommand.spec, InstanceCopyCommand.spec, InstanceMoveCommand.spec, InstanceExportCommand.spec, InstanceComponentListCommand.spec, InstanceComponentVersionsCommand.spec, InstanceComponentSetCommand.spec, InstanceComponentRestoreCommand.spec, DirectoryListCommand.spec, DirectorySelectedCommand.spec, DirectoryScanCommand.spec, DirectoryAddCommand.spec, DirectorySelectCommand.spec, DirectoryRefreshCommand.spec, DirectoryRemoveCommand.spec, DirectoryRenameCommand.spec, DirectoryRelocateCommand.spec, DirectoryRestoreCommand.spec, DirectoryRunGetCommand.spec, DirectoryRunSetCommand.spec, DirectoryRunRelocateCommand.spec, JavaListCommand.spec, JavaAvailableCommand.spec, JavaAddCommand.spec, JavaForgetCommand.spec, JavaDefaultCommand.spec, JavaReferencesCommand.spec, JavaInstallCommand.spec, JavaRepairCommand.spec, JavaRemoveCommand.spec, AccountListCommand.spec, AccountSelectedCommand.spec, AccountShowCommand.spec, AccountAddOfflineCommand.spec, AccountSelectCommand.spec, AccountRefreshCommand.spec, AccountRemoveCommand.spec, AccountLogoutCommand.spec, AccountLoginStartCommand.spec, AccountLoginCompleteCommand.spec, AccountLoginCancelCommand.spec, AccountServiceKeyStatusCommand.spec, AccountServiceKeySetCommand.spec, AccountServiceKeyRemoveCommand.spec, LaunchPreflightCommand.spec, LaunchStartCommand.spec, SessionListCommand.spec, SessionShowCommand.spec, SessionWaitCommand.spec, SessionQuitCommand.spec, SessionStopCommand.spec, SessionLogsCommand.spec, SessionDiagnoseCommand.spec, SessionExportCommand.spec]
}

