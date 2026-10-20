import RuriLocalization
import ArgumentParser
import Foundation
import RuriCore

struct SchemaCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schema"], summary: Messages.CLIInterface.schemaCommandHelp.localized, operands: [
        .init(name: "resource", type: "string", required: false, help: Messages.CLIInterface.argumentCommandPath.localized, values: [], role: .commandPath),
        .init(name: "action", type: "string", required: false, help: Messages.CLIInterface.argumentCommandPath.localized, values: [], role: .commandPath),
        .init(name: "subaction", type: "string", required: false, help: Messages.CLIInterface.argumentCommandPath.localized, values: [], role: .commandPath)
    ], options: [
        .init(name: "input", type: "bool", required: false, help: Messages.CLIExperience.inputSchema.localized),
        .init(name: "output-schema", type: "bool", required: false, help: Messages.CLIExperience.outputSchema.localized),
        .init(name: "scope", type: "string", required: false, help: Messages.CLIExperience.schemaScope.localized, values: ["app", "defaults", "instance"]),
        .init(name: "full", type: "bool", required: false, help: Messages.CLIExperience.fullSchema.localized)
    ], examples: ["ruri schema instance", "ruri schema config apply --input --scope instance --json"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentResource: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentAction: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentSubaction: String?
    var operands: [String] { [argumentResource, argumentAction, argumentSubaction].compactMap { $0 } }
    @Flag(help: ArgumentHelp(Messages.CLIExperience.inputSchema.localized)) var input = false
    @Flag(name: .customLong("output-schema"), help: ArgumentHelp(Messages.CLIExperience.outputSchema.localized)) var outputSchema = false
    @Option(help: ArgumentHelp(Messages.CLIExperience.schemaScope.localized), completion: Self.completion(option: "scope")) var scope: String?
    @Flag(help: ArgumentHelp(Messages.CLIExperience.fullSchema.localized)) var full = false
    var parameters: [String: Value] { ["input": .bool(input), "output-schema": .bool(outputSchema), "scope": .text(scope), "full": .bool(full)].filter { $0.value != .null } }
}

struct AppInfoCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","info"], summary: Messages.CLIInterface.appVersionHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","language","get"], summary: Messages.CLIInterface.appLanguageGetHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AppLanguageSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["app","language","set"], summary: Messages.CLIInterface.appLanguageSetHelp.localized, operands: [
        .init(name: "language", type: "string", required: true, help: Messages.CLIInterface.argumentLanguage.localized, values: ["system"] + LocalizationContext.supportedLanguages, role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri app language set zh-Hans"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentLanguage: String?
    var operands: [String] { [argumentLanguage].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CliStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","status"], summary: Messages.CLIInterface.cliStatusHelp.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.cliUninstallDirectoryHelp.localized, values: [], role: .folder)
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.cliUninstallDirectoryHelp.localized), completion: Self.completion(option: "bin-dir")) var optionBinDir: String?
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir)
    ].filter { $0.value != .null } }
}

struct CliInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","install"], summary: Messages.CLIInterface.cliInstallHelp.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.cliInstallDirectoryHelp.localized, values: [], role: .folder),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: ["ruri cli install", "ruri cli install --bin-dir ~/.local/bin"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.cliInstallDirectoryHelp.localized), completion: Self.completion(option: "bin-dir")) var optionBinDir: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CliUninstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cli","uninstall"], summary: Messages.CLIInterface.cliUninstallHelp.localized, operands: [

    ], options: [
        .init(name: "bin-dir", type: "string", required: false, help: Messages.CLIInterface.cliUninstallDirectoryHelp.localized, values: [], role: .folder),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: true, examples: ["ruri cli uninstall --yes"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("bin-dir"), help: ArgumentHelp(Messages.CLIInterface.cliUninstallDirectoryHelp.localized), completion: Self.completion(option: "bin-dir")) var optionBinDir: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "bin-dir": .text(optionBinDir),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct ConfigGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","get"], summary: Messages.CLIInterface.configGetHelp.localized, operands: [
        .init(name: "key", type: "string", required: false, help: Messages.CLIInterface.argumentConfigKey.localized, values: [], role: .configKey)
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: [], role: .scope),
        .init(name: "show-secrets", type: "bool", required: false, help: Messages.CLIInterface.showEnvironmentValuesHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri config get --scope defaults", "ruri config get memory --scope instance:Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentKey: String?
    var operands: [String] { [argumentKey].compactMap { $0 } }
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized), completion: Self.completion(option: "scope")) var optionScope: String?
    @Flag(name: .customLong("show-secrets"), help: ArgumentHelp(Messages.CLIInterface.showEnvironmentValuesHelp.localized)) var optionShowSecrets = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "show-secrets": .bool(optionShowSecrets)
    ].filter { $0.value != .null } }
}

struct ConfigSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","set"], summary: Messages.CLIInterface.configSetHelp.localized, operands: [
        .init(name: "key", type: "string", required: true, help: Messages.CLIInterface.argumentConfigKey.localized, values: [], role: .configKey),
        .init(name: "value", type: "string", required: true, help: Messages.CLIInterface.argumentConfigValue.localized, values: [], role: .configValue)
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: [], role: .scope),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config set memory.maximumMB 6144 --scope defaults", "ruri config set memory.mode manual --scope instance:Survival", "ruri config set java.path \"/Library/Java/JavaVirtualMachines/zulu-21.jdk\" --scope defaults"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentKey: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentValue: String?
    var operands: [String] { [argumentKey, argumentValue].compactMap { $0 } }
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized), completion: Self.completion(option: "scope")) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized), completion: Self.completion(option: "if-revision")) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigApplyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","apply"], summary: Messages.CLIInterface.configApplyHelp.localized, operands: [

    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: [], role: .scope),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.configPatchFileHelp.localized, values: [], role: .file),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config apply --scope instance:Survival --file patch.json --dry-run", "printf '{\"set\":{\"concurrentDownloads\":8}}' | ruri config apply --scope app --file -"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized), completion: Self.completion(option: "scope")) var optionScope: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.configPatchFileHelp.localized), completion: Self.completion(option: "file")) var optionFile: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized), completion: Self.completion(option: "if-revision")) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "file": .text(optionFile),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigResetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","reset"], summary: Messages.CLIInterface.configResetHelp.localized, operands: [
        .init(name: "key", type: "string", required: true, help: Messages.CLIInterface.argumentConfigKey.localized, values: [], role: .configKey)
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: [], role: .scope),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config reset window --scope defaults"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentKey: String?
    var operands: [String] { [argumentKey].compactMap { $0 } }
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized), completion: Self.completion(option: "scope")) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized), completion: Self.completion(option: "if-revision")) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigInheritCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","inherit"], summary: Messages.CLIInterface.configInheritHelp.localized, operands: [
        .init(name: "group", type: "string", required: true, help: Messages.CLIInterface.argumentConfigGroup.localized, values: [], role: .configGroup)
    ], options: [
        .init(name: "scope", type: "string", required: true, help: Messages.CLIInterface.configScopeHelp.localized, values: [], role: .scope),
        .init(name: "if-revision", type: "string", required: false, help: Messages.CLIInterface.ifRevisionHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri config inherit memory --scope instance:Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentGroup: String?
    var operands: [String] { [argumentGroup].compactMap { $0 } }
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIInterface.configScopeHelp.localized), completion: Self.completion(option: "scope")) var optionScope: String?
    @Option(name: .customLong("if-revision"), help: ArgumentHelp(Messages.CLIInterface.ifRevisionHelp.localized), completion: Self.completion(option: "if-revision")) var optionIfRevision: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "scope": .text(optionScope),
        "if-revision": .text(optionIfRevision),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ConfigFieldsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["config","fields"], summary: Messages.CLIInterface.configFieldsHelp.localized, operands: [
        .init(name: "prefix", type: "string", required: false, help: Messages.CLIInterface.argumentConfigPrefix.localized, values: [], role: .configKey)
    ], options: [
        .init(name: "scope", type: "string", required: false, help: Messages.CLIExperience.schemaScope.localized, values: ["app", "defaults", "instance"])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri config fields memory", "ruri config fields --scope app"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentPrefix: String?
    var operands: [String] { [argumentPrefix].compactMap { $0 } }
    @Option(name: .customLong("scope"), help: ArgumentHelp(Messages.CLIExperience.schemaScope.localized), completion: Self.completion(option: "scope")) var optionScope: String?
    var parameters: [String: Value] { ["scope": .text(optionScope)].filter { $0.value != .null } }
}

struct InstanceListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","list"], summary: Messages.CLIInterface.instanceListHelp.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.exactNameFilterHelp.localized, values: []),
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.directoryFilterHelp.localized, values: [], role: .directory),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri instance list", "ruri instance list --directory default --all"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.exactNameFilterHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.directoryFilterHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceSelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","selected"], summary: Messages.CLIInterface.instanceSelectedHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","show"], summary: Messages.CLIInterface.instanceShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "name", type: "string", required: false, help: Messages.CLIInterface.instanceNameLookupHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri instance show Survival", "ruri instance show 3f2a1b4c"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.instanceNameLookupHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    var parameters: [String: Value] { [
        "name": .text(optionName)
    ].filter { $0.value != .null } }
}

struct InstanceVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","versions"], summary: Messages.CLIInterface.minecraftVersionsHelp.localized, operands: [

    ], options: [
        .init(name: "snapshots", type: "bool", required: false, help: Messages.CLIInterface.includeSnapshotsHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri instance versions --limit 10", "ruri instance versions --snapshots"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Flag(name: .customLong("snapshots"), help: ArgumentHelp(Messages.CLIInterface.includeSnapshotsHelp.localized)) var optionSnapshots = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "snapshots": .bool(optionSnapshots),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceCreateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","create"], summary: Messages.CLIInterface.instanceCreateHelp.localized, operands: [

    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.instanceNameHelp.localized, values: []),
        .init(name: "game", type: "string", required: true, help: Messages.CLIInterface.minecraftVersionHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceTargetDirectoryHelp.localized, values: [], role: .directory),
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.instanceCreateLoadersHelp.localized, values: []),
        .init(name: "no-install", type: "bool", required: false, help: Messages.CLIInterface.instanceRecordOnlyHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance create --name Survival --game 1.21.1 --directory default", "ruri instance create --name Fabric --game 1.21.1 --directory default --component fabric=0.16.9", "ruri instance create --name Survival --game 1.21.1 --directory default --no-install --json"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.instanceNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.minecraftVersionHelp.localized), completion: Self.completion(option: "game")) var optionGame: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceTargetDirectoryHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Option(name: .customLong("component"), help: ArgumentHelp(Messages.CLIInterface.instanceCreateLoadersHelp.localized), completion: Self.completion(option: "component")) var optionComponent: [String] = []
    @Flag(name: .customLong("no-install"), help: ArgumentHelp(Messages.CLIInterface.instanceRecordOnlyHelp.localized)) var optionNoInstall = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
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
    static var spec: CommandSpec { CommandSpec(path: ["instance","install"], summary: Messages.CLIInterface.instanceInstallHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance install Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRepairCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","repair"], summary: Messages.CLIInterface.instanceRepairHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance repair Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceSelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","select"], summary: Messages.CLIInterface.instanceSelectHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance select Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRenameCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","rename"], summary: Messages.CLIInterface.instanceRenameHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.argumentNewName.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance rename Survival \"Survival 1.21\""]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentName: String?
    var operands: [String] { [argumentInstance, argumentName].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceFavoriteCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","favorite"], summary: Messages.CLIInterface.instancePinHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "enabled", type: "string", required: true, help: Messages.CLIInterface.argumentPinned.localized, values: ["true", "false"], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance favorite Survival true"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentEnabled: String?
    var operands: [String] { [argumentInstance, argumentEnabled].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","remove"], summary: Messages.CLIInterface.instanceRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri instance remove Survival --dry-run", "ruri instance remove Survival --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct InstanceIconCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","icon"], summary: Messages.CLIInterface.instanceIconHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "file", type: "string", required: false, help: Messages.CLIInterface.instanceIconFileHelp.localized, values: [], role: .file),
        .init(name: "glyph", type: "string", required: false, help: Messages.CLIInterface.instanceIconGlyphHelp.localized, values: InstanceIconGlyph.allCases.map(\.rawValue)),
        .init(name: "tint", type: "string", required: false, help: Messages.CLIInterface.instanceIconTintHelp.localized, values: InstanceIconTint.allCases.map(\.rawValue), defaultValue: "slate"),
        .init(name: "reset", type: "bool", required: false, help: Messages.CLIInterface.instanceIconResetHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance icon Survival --glyph tree --tint green", "ruri instance icon Survival --file icon.png", "ruri instance icon Survival --reset"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.instanceIconFileHelp.localized), completion: Self.completion(option: "file")) var optionFile: String?
    @Option(name: .customLong("glyph"), help: ArgumentHelp(Messages.CLIInterface.instanceIconGlyphHelp.localized), completion: Self.completion(option: "glyph")) var optionGlyph: String?
    @Option(name: .customLong("tint"), help: ArgumentHelp(Messages.CLIInterface.instanceIconTintHelp.localized), completion: Self.completion(option: "tint")) var optionTint: String?
    @Flag(name: .customLong("reset"), help: ArgumentHelp(Messages.CLIInterface.instanceIconResetHelp.localized)) var optionReset = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "file": .text(optionFile),
        "glyph": .text(optionGlyph),
        "tint": .text(optionTint),
        "reset": .bool(optionReset),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceCopyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","copy"], summary: Messages.CLIInterface.instanceCopyHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceTargetDirectoryHelp.localized, values: [], role: .directory),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.excludeWorldsHelp.localized, values: []),
        .init(name: "with-backups", type: "bool", required: false, help: Messages.CLIInterface.includeWorldBackupsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance copy Survival --name \"Survival copy\" --directory default"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceTargetDirectoryHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Flag(name: .customLong("without-worlds"), help: ArgumentHelp(Messages.CLIInterface.excludeWorldsHelp.localized)) var optionWithoutWorlds = false
    @Flag(name: .customLong("with-backups"), help: ArgumentHelp(Messages.CLIInterface.includeWorldBackupsHelp.localized)) var optionWithBackups = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "name": .text(optionName),
        "without-worlds": .bool(optionWithoutWorlds),
        "with-backups": .bool(optionWithBackups),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceMoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","move"], summary: Messages.CLIInterface.instanceMoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceTargetDirectoryHelp.localized, values: [], role: .directory),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance move Survival --directory Games --dry-run"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceTargetDirectoryHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","export"], summary: Messages.CLIInterface.instanceExportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentArchiveToCreate.localized, values: [], role: .newFile)
    ], options: [
        .init(name: "format", type: "string", required: false, help: Messages.CLIInterface.instanceArchiveFormatHelp.localized, values: ["ruri","complete","multimc","mcbbs","mrpack"], defaultValue: "ruri"),
        .init(name: "without-worlds", type: "bool", required: false, help: Messages.CLIInterface.excludeWorldsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance export Survival ~/Desktop/Survival.mrpack --format mrpack"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentFile].compactMap { $0 } }
    @Option(name: .customLong("format"), help: ArgumentHelp(Messages.CLIInterface.instanceArchiveFormatHelp.localized), completion: Self.completion(option: "format")) var optionFormat: String?
    @Flag(name: .customLong("without-worlds"), help: ArgumentHelp(Messages.CLIInterface.excludeWorldsHelp.localized)) var optionWithoutWorlds = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "format": .text(optionFormat),
        "without-worlds": .bool(optionWithoutWorlds),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceComponentListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","list"], summary: Messages.CLIInterface.instanceComponentsShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri instance component list Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct InstanceComponentVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","versions"], summary: Messages.CLIInterface.instanceComponentsVersionsHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "loader", type: "string", required: true, help: Messages.CLIInterface.argumentLoader.localized, values: LoaderKind.allCases.filter { $0 != .vanilla }.map(\.rawValue), role: .text)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri instance component versions Survival fabric --limit 5"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentLoader: String?
    var operands: [String] { [argumentInstance, argumentLoader].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct InstanceComponentSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","set"], summary: Messages.CLIInterface.instanceComponentsSetHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "component", type: "strings", required: false, help: Messages.CLIInterface.instanceComponentLoadersHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance component set Survival --component fabric=0.16.9 --dry-run"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("component"), help: ArgumentHelp(Messages.CLIInterface.instanceComponentLoadersHelp.localized), completion: Self.completion(option: "component")) var optionComponent: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "component": .array(optionComponent.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct InstanceComponentRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","component","restore"], summary: Messages.CLIInterface.instanceComponentsRestoreHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri instance component restore Survival --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DirectoryListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","list"], summary: Messages.CLIInterface.directoryListHelp.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DirectorySelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","selected"], summary: Messages.CLIInterface.directorySelectedHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryScanCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","scan"], summary: Messages.CLIInterface.directoryInspectHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentMinecraftFolder.localized, values: [], role: .folder)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri directory scan \"$HOME/Library/Application Support/minecraft\""]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentPath: String?
    var operands: [String] { [argumentPath].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DirectoryAddCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","add"], summary: Messages.CLIInterface.directoryAddHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentFolderToAdd.localized, values: [], role: .folder)
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.directoryNameHelp.localized, values: []),
        .init(name: "layout", type: "string", required: false, help: Messages.CLIInterface.directoryLayoutHelp.localized, values: ["minecraft","managed"], defaultValue: "minecraft"),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri directory add \"$HOME/Library/Application Support/minecraft\" --name Official", "ruri directory add ~/Games/Ruri --name Games --layout managed"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentPath: String?
    var operands: [String] { [argumentPath].compactMap { $0 } }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.directoryNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("layout"), help: ArgumentHelp(Messages.CLIInterface.directoryLayoutHelp.localized), completion: Self.completion(option: "layout")) var optionLayout: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "layout": .text(optionLayout),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectorySelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","select"], summary: Messages.CLIInterface.directorySelectHelp.localized, operands: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.argumentDirectory.localized, values: [], role: .directory)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri directory select Games"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentDirectory: String?
    var operands: [String] { [argumentDirectory].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRefreshCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","refresh"], summary: Messages.CLIInterface.directoryRefreshHelp.localized, operands: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.argumentDirectory.localized, values: [], role: .directory)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentDirectory: String?
    var operands: [String] { [argumentDirectory].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","remove"], summary: Messages.CLIInterface.directoryRemoveHelp.localized, operands: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.argumentDirectory.localized, values: [], role: .directory)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri directory remove Official --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentDirectory: String?
    var operands: [String] { [argumentDirectory].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DirectoryRenameCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","rename"], summary: Messages.CLIInterface.directoryRenameHelp.localized, operands: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.argumentDirectory.localized, values: [], role: .directory),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.argumentNewName.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri directory rename Official Vanilla"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentDirectory: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentName: String?
    var operands: [String] { [argumentDirectory, argumentName].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRelocateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","relocate"], summary: Messages.CLIInterface.directoryRelocateHelp.localized, operands: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.argumentDirectory.localized, values: [], role: .directory),
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentNewLocation.localized, values: [], role: .folder)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri directory relocate Games /Volumes/External/Ruri"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentDirectory: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentPath: String?
    var operands: [String] { [argumentDirectory, argumentPath].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","restore"], summary: Messages.CLIInterface.directoryRecoverHelp.localized, operands: [
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.argumentDirectory.localized, values: [], role: .directory),
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentDetachedLocation.localized, values: [], role: .folder)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentDirectory: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentPath: String?
    var operands: [String] { [argumentDirectory, argumentPath].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRunGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","get"], summary: Messages.CLIInterface.instanceRunDirectoryShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri directory run get Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DirectoryRunSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","set"], summary: Messages.CLIInterface.instanceRunDirectorySetHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "mode", type: "string", required: true, help: Messages.CLIInterface.argumentRunMode.localized, values: GameRunDirectory.allCases.map(\.rawValue), role: .text)
    ], options: [
        .init(name: "path", type: "string", required: false, help: Messages.CLIInterface.customRunDirectoryPathHelp.localized, values: [], role: .folder),
        .init(name: "copy", type: "bool", required: false, help: Messages.CLIInterface.copyGameFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri directory run set Survival shared", "ruri directory run set Survival custom --path ~/Games/Survival --copy"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentMode: String?
    var operands: [String] { [argumentInstance, argumentMode].compactMap { $0 } }
    @Option(name: .customLong("path"), help: ArgumentHelp(Messages.CLIInterface.customRunDirectoryPathHelp.localized), completion: Self.completion(option: "path")) var optionPath: String?
    @Flag(name: .customLong("copy"), help: ArgumentHelp(Messages.CLIInterface.copyGameFilesHelp.localized)) var optionCopy = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "path": .text(optionPath),
        "copy": .bool(optionCopy),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DirectoryRunRelocateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["directory","run","relocate"], summary: Messages.CLIInterface.instanceRunDirectoryRelocateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentCustomRunDirectory.localized, values: [], role: .folder)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri directory run relocate Survival /Volumes/External/Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentPath: String?
    var operands: [String] { [argumentInstance, argumentPath].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","list"], summary: Messages.CLIInterface.javaListHelp.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaAvailableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","available"], summary: Messages.CLIInterface.javaCatalogHelp.localized, operands: [

    ], options: [
        .init(name: "major", type: "int", required: false, help: Messages.CLIInterface.javaMajorFilterHelp.localized, values: []),
        .init(name: "architecture", type: "string", required: false, help: Messages.CLIInterface.javaArchitectureFilterHelp.localized, values: ["aarch64","x86_64"]),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri java available --major 21"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("major"), help: ArgumentHelp(Messages.CLIInterface.javaMajorFilterHelp.localized), completion: Self.completion(option: "major")) var optionMajor: Int?
    @Option(name: .customLong("architecture"), help: ArgumentHelp(Messages.CLIInterface.javaArchitectureFilterHelp.localized), completion: Self.completion(option: "architecture")) var optionArchitecture: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "major": optionMajor.map(Value.integer) ?? .null,
        "architecture": .text(optionArchitecture),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaAddCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","add"], summary: Messages.CLIInterface.javaAddHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentJavaPath.localized, values: [], role: .file)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri java add /Library/Java/JavaVirtualMachines/zulu-21.jdk"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentPath: String?
    var operands: [String] { [argumentPath].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaForgetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","forget"], summary: Messages.CLIInterface.javaForgetHelp.localized, operands: [
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentJavaPath.localized, values: [], role: .file)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentPath: String?
    var operands: [String] { [argumentPath].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaDefaultCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","default"], summary: Messages.CLIInterface.javaDefaultHelp.localized, operands: [
        .init(name: "path-or-automatic", type: "string", required: true, help: Messages.CLIInterface.argumentJavaDefault.localized, values: [], role: .file)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri java default automatic"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentPathOrAutomatic: String?
    var operands: [String] { [argumentPathOrAutomatic].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaReferencesCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","references"], summary: Messages.CLIInterface.javaReferencesHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: Messages.CLIInterface.argumentManagedJava.localized, values: [], role: .text)
    ], options: [
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.javaCheckIncompleteInstallationsHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentId: String?
    var operands: [String] { [argumentId].compactMap { $0 } }
    @Flag(name: .customLong("partial"), help: ArgumentHelp(Messages.CLIInterface.javaCheckIncompleteInstallationsHelp.localized)) var optionPartial = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "partial": .bool(optionPartial),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct JavaInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","install"], summary: Messages.CLIInterface.javaInstallHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: Messages.CLIInterface.argumentJavaCatalogID.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentId: String?
    var operands: [String] { [argumentId].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRepairCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","repair"], summary: Messages.CLIInterface.javaRepairHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: Messages.CLIInterface.argumentManagedJava.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentId: String?
    var operands: [String] { [argumentId].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct JavaRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["java","remove"], summary: Messages.CLIInterface.javaRemoveHelp.localized, operands: [
        .init(name: "id", type: "string", required: true, help: Messages.CLIInterface.argumentManagedJava.localized, values: [], role: .text)
    ], options: [
        .init(name: "reset-references", type: "bool", required: false, help: Messages.CLIInterface.javaResetReferencesHelp.localized, values: []),
        .init(name: "partial", type: "bool", required: false, help: Messages.CLIInterface.javaCleanIncompleteInstallationHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentId: String?
    var operands: [String] { [argumentId].compactMap { $0 } }
    @Flag(name: .customLong("reset-references"), help: ArgumentHelp(Messages.CLIInterface.javaResetReferencesHelp.localized)) var optionResetReferences = false
    @Flag(name: .customLong("partial"), help: ArgumentHelp(Messages.CLIInterface.javaCleanIncompleteInstallationHelp.localized)) var optionPartial = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "reset-references": .bool(optionResetReferences),
        "partial": .bool(optionPartial),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","list"], summary: Messages.CLIInterface.accountListHelp.localized, operands: [

    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct AccountSelectedCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","selected"], summary: Messages.CLIInterface.accountSelectedHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","show"], summary: Messages.CLIInterface.accountShowHelp.localized, operands: [
        .init(name: "account", type: "string", required: true, help: Messages.CLIInterface.argumentAccount.localized, values: [], role: .account)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAccount: String?
    var operands: [String] { [argumentAccount].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountAddOfflineCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","add-offline"], summary: Messages.CLIInterface.accountOfflineHelp.localized, operands: [
        .init(name: "username", type: "string", required: true, help: Messages.CLIInterface.argumentOfflineUsername.localized, values: [], role: .text)
    ], options: [
        .init(name: "no-select", type: "bool", required: false, help: Messages.CLIInterface.keepCurrentAccountHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri account add-offline Steve"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentUsername: String?
    var operands: [String] { [argumentUsername].compactMap { $0 } }
    @Flag(name: .customLong("no-select"), help: ArgumentHelp(Messages.CLIInterface.keepCurrentAccountHelp.localized)) var optionNoSelect = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "no-select": .bool(optionNoSelect),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountSelectCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","select"], summary: Messages.CLIInterface.accountSelectHelp.localized, operands: [
        .init(name: "account", type: "string", required: true, help: Messages.CLIInterface.argumentAccount.localized, values: [], role: .account)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri account select Steve"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAccount: String?
    var operands: [String] { [argumentAccount].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRefreshCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","refresh"], summary: Messages.CLIInterface.accountRefreshHelp.localized, operands: [
        .init(name: "account", type: "string", required: true, help: Messages.CLIInterface.argumentAccount.localized, values: [], role: .account)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAccount: String?
    var operands: [String] { [argumentAccount].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","remove"], summary: Messages.CLIInterface.accountRemoveHelp.localized, operands: [
        .init(name: "account", type: "string", required: true, help: Messages.CLIInterface.argumentAccount.localized, values: [], role: .account)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAccount: String?
    var operands: [String] { [argumentAccount].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountLogoutCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","logout"], summary: Messages.CLIInterface.accountLogoutHelp.localized, operands: [
        .init(name: "account", type: "string", required: true, help: Messages.CLIInterface.argumentAccount.localized, values: [], role: .account)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentAccount: String?
    var operands: [String] { [argumentAccount].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct AccountLoginStartCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","start"], summary: Messages.CLIInterface.accountLoginStartHelp.localized, operands: [

    ], options: [
        .init(name: "provider", type: "string", required: true, help: Messages.CLIInterface.loginProviderHelp.localized, values: ["microsoft","external"]),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.reauthenticateAccountHelp.localized, values: [], role: .account),
        .init(name: "server", type: "string", required: false, help: Messages.CLIInterface.externalLoginServerHelp.localized, values: []),
        .init(name: "username", type: "string", required: false, help: Messages.CLIInterface.externalLoginIdentityHelp.localized, values: []),
        .init(name: "password-stdin", type: "bool", required: false, help: Messages.CLIInterface.passwordStdinHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: ["ruri account login start --provider microsoft", "ruri account login start --provider external --server https://example.com/api/yggdrasil --username alex@example.com --password-stdin < password.txt"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.loginProviderHelp.localized), completion: Self.completion(option: "provider")) var optionProvider: String?
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.reauthenticateAccountHelp.localized), completion: Self.completion(option: "account")) var optionAccount: String?
    @Option(name: .customLong("server"), help: ArgumentHelp(Messages.CLIInterface.externalLoginServerHelp.localized), completion: Self.completion(option: "server")) var optionServer: String?
    @Option(name: .customLong("username"), help: ArgumentHelp(Messages.CLIInterface.externalLoginIdentityHelp.localized), completion: Self.completion(option: "username")) var optionUsername: String?
    @Flag(name: .customLong("password-stdin"), help: ArgumentHelp(Messages.CLIInterface.passwordStdinHelp.localized)) var optionPasswordStdin = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
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
    static var spec: CommandSpec { CommandSpec(path: ["account","login","complete"], summary: Messages.CLIInterface.accountLoginCompleteHelp.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: Messages.CLIInterface.argumentLoginFlow.localized, values: [], role: .text)
    ], options: [
        .init(name: "profile", type: "string", required: false, help: Messages.CLIInterface.externalLoginProfileIdHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: true, examples: ["ruri account login complete <flow>"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentFlow: String?
    var operands: [String] { [argumentFlow].compactMap { $0 } }
    @Option(name: .customLong("profile"), help: ArgumentHelp(Messages.CLIInterface.externalLoginProfileIdHelp.localized), completion: Self.completion(option: "profile")) var optionProfile: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "profile": .text(optionProfile),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountLoginCancelCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","login","cancel"], summary: Messages.CLIInterface.accountLoginCancelHelp.localized, operands: [
        .init(name: "flow", type: "string", required: true, help: Messages.CLIInterface.argumentLoginFlow.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentFlow: String?
    var operands: [String] { [argumentFlow].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","status"], summary: Messages.CLIInterface.curseForgeKeyStatusHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct AccountServiceKeySetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","set"], summary: Messages.CLIInterface.curseForgeKeySetHelp.localized, operands: [

    ], options: [
        .init(name: "stdin", type: "bool", required: true, help: Messages.CLIInterface.apiKeyStdinHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri account service-key set --stdin < key.txt"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Flag(name: .customLong("stdin"), help: ArgumentHelp(Messages.CLIInterface.apiKeyStdinHelp.localized)) var optionStdin = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "stdin": .bool(optionStdin),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct AccountServiceKeyRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["account","service-key","remove"], summary: Messages.CLIInterface.curseForgeKeyClearHelp.localized, operands: [

    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct LaunchPreflightCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["launch","preflight"], summary: Messages.CLIInterface.launchCheckHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "server", type: "string", required: false, help: Messages.CLIInterface.launchServerHelp.localized, values: []),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.launchAccountHelp.localized, values: [], role: .account),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.quickPlayWorldHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri launch preflight Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("server"), help: ArgumentHelp(Messages.CLIInterface.launchServerHelp.localized), completion: Self.completion(option: "server")) var optionServer: String?
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.launchAccountHelp.localized), completion: Self.completion(option: "account")) var optionAccount: String?
    @Option(name: .customLong("world"), help: ArgumentHelp(Messages.CLIInterface.quickPlayWorldHelp.localized), completion: Self.completion(option: "world")) var optionWorld: String?
    var parameters: [String: Value] { [
        "server": .text(optionServer),
        "account": .text(optionAccount),
        "world": .text(optionWorld)
    ].filter { $0.value != .null } }
}

struct LaunchStartCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["launch","start"], summary: Messages.CLIInterface.launchStartHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "server", type: "string", required: false, help: Messages.CLIInterface.launchServerHelp.localized, values: []),
        .init(name: "account", type: "string", required: false, help: Messages.CLIInterface.launchAccountHelp.localized, values: [], role: .account),
        .init(name: "world", type: "string", required: false, help: Messages.CLIInterface.quickPlayWorldHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri launch start Survival", "ruri launch start Survival --account Steve --world \"New World\"", "ruri launch start Survival --server play.example.com"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("server"), help: ArgumentHelp(Messages.CLIInterface.launchServerHelp.localized), completion: Self.completion(option: "server")) var optionServer: String?
    @Option(name: .customLong("account"), help: ArgumentHelp(Messages.CLIInterface.launchAccountHelp.localized), completion: Self.completion(option: "account")) var optionAccount: String?
    @Option(name: .customLong("world"), help: ArgumentHelp(Messages.CLIInterface.quickPlayWorldHelp.localized), completion: Self.completion(option: "world")) var optionWorld: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "server": .text(optionServer),
        "account": .text(optionAccount),
        "world": .text(optionWorld),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SessionListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","list"], summary: Messages.CLIInterface.sessionListHelp.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.sessionInstanceIdFilterHelp.localized, values: [], role: .instance),
        .init(name: "search", type: "string", required: false, help: Messages.CLIInterface.sessionInstanceNameFilterHelp.localized, values: []),
        .init(name: "problems", type: "bool", required: false, help: Messages.CLIInterface.problemSessionsOnlyHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri session list --instance Survival", "ruri session list --problems"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.sessionInstanceIdFilterHelp.localized), completion: Self.completion(option: "instance")) var optionInstance: String?
    @Option(name: .customLong("search"), help: ArgumentHelp(Messages.CLIInterface.sessionInstanceNameFilterHelp.localized), completion: Self.completion(option: "search")) var optionSearch: String?
    @Flag(name: .customLong("problems"), help: ArgumentHelp(Messages.CLIInterface.problemSessionsOnlyHelp.localized)) var optionProblems = false
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
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
    static var spec: CommandSpec { CommandSpec(path: ["session","show"], summary: Messages.CLIInterface.sessionShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "session", type: "string", required: true, help: Messages.CLIInterface.argumentSession.localized, values: [], role: .session)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri session show Survival 3f2a1b4c"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentSession: String?
    var operands: [String] { [argumentInstance, argumentSession].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionWaitCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","wait"], summary: Messages.CLIInterface.sessionWaitHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "session", type: "string", required: true, help: Messages.CLIInterface.argumentSession.localized, values: [], role: .session)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri session wait Survival 3f2a1b4c"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentSession: String?
    var operands: [String] { [argumentInstance, argumentSession].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionQuitCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","quit"], summary: Messages.CLIInterface.sessionStopHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "session", type: "string", required: true, help: Messages.CLIInterface.argumentSession.localized, values: [], role: .session)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri session quit Survival 3f2a1b4c"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentSession: String?
    var operands: [String] { [argumentInstance, argumentSession].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SessionStopCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","stop"], summary: Messages.CLIInterface.sessionKillHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "session", type: "string", required: true, help: Messages.CLIInterface.argumentSession.localized, values: [], role: .session)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri session stop Survival 3f2a1b4c --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentSession: String?
    var operands: [String] { [argumentInstance, argumentSession].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct SessionLogsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","logs"], summary: Messages.CLIInterface.sessionLogsHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "session", type: "string", required: true, help: Messages.CLIInterface.argumentSession.localized, values: [], role: .session)
    ], options: [
        .init(name: "follow", type: "bool", required: false, help: Messages.CLIInterface.sessionLogFollowHelp.localized, values: []),
        .init(name: "source", type: "string", required: false, help: Messages.CLIInterface.sessionLogSourceHelp.localized, values: ["output","preparation","latest","debug"], defaultValue: "output"),
        .init(name: "lines", type: "int", required: false, help: Messages.CLIInterface.sessionLogLineLimitHelp.localized, values: [], defaultValue: "200", minimum: 1, maximum: 10000)
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri session logs Survival 3f2a1b4c --follow", "ruri session logs Survival 3f2a1b4c --source latest --lines 100", "ruri session logs <instance> <session> --follow --output ndjson"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentSession: String?
    var operands: [String] { [argumentInstance, argumentSession].compactMap { $0 } }
    @Flag(name: .customLong("follow"), help: ArgumentHelp(Messages.CLIInterface.sessionLogFollowHelp.localized)) var optionFollow = false
    @Option(name: .customLong("source"), help: ArgumentHelp(Messages.CLIInterface.sessionLogSourceHelp.localized), completion: Self.completion(option: "source")) var optionSource: String?
    @Option(name: .customLong("lines"), help: ArgumentHelp(Messages.CLIInterface.sessionLogLineLimitHelp.localized), completion: Self.completion(option: "lines")) var optionLines: Int?
    var parameters: [String: Value] { [
        "follow": .bool(optionFollow),
        "source": .text(optionSource),
        "lines": optionLines.map(Value.integer) ?? .null
    ].filter { $0.value != .null } }
}

struct SessionDiagnoseCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","diagnose"], summary: Messages.CLIInterface.sessionAnalyzeHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "session", type: "string", required: true, help: Messages.CLIInterface.argumentSession.localized, values: [], role: .session)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri session diagnose Survival 3f2a1b4c"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentSession: String?
    var operands: [String] { [argumentInstance, argumentSession].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct SessionExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["session","export"], summary: Messages.CLIInterface.sessionExportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "session", type: "string", required: true, help: Messages.CLIInterface.argumentSession.localized, values: [], role: .session),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentFileToCreate.localized, values: [], role: .newFile)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri session export Survival 3f2a1b4c ~/Desktop/Report.zip"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentSession: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentSession, argumentFile].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CatalogSearchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","search"], summary: Messages.CLIInterface.catalogSearchHelp.localized, operands: [
        .init(name: "query", type: "string", required: false, help: Messages.CLIInterface.argumentSearchQuery.localized, values: [], role: .text)
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"], defaultValue: "modrinth"),
        .init(name: "type", type: "string", required: false, help: Messages.CLIInterface.catalogProjectTypeHelp.localized, values: ["mod","modpack","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "game", type: "string", required: false, help: Messages.CLIInterface.minecraftVersionFilterHelp.localized, values: []),
        .init(name: "loader", type: "string", required: false, help: Messages.CLIInterface.loaderFilterHelp.localized, values: []),
        .init(name: "category", type: "string", required: false, help: Messages.CLIInterface.catalogCategoryHelp.localized, values: []),
        .init(name: "sort", type: "string", required: false, help: Messages.CLIInterface.catalogSortHelp.localized, values: ["relevance","downloads","updated","newest"], defaultValue: "relevance"),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri catalog search sodium --loader fabric --game 1.21.1", "ruri catalog search --type modpack --sort downloads"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentQuery: String?
    var operands: [String] { [argumentQuery].compactMap { $0 } }
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized), completion: Self.completion(option: "provider")) var optionProvider: String?
    @Option(name: .customLong("type"), help: ArgumentHelp(Messages.CLIInterface.catalogProjectTypeHelp.localized), completion: Self.completion(option: "type")) var optionType: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.minecraftVersionFilterHelp.localized), completion: Self.completion(option: "game")) var optionGame: String?
    @Option(name: .customLong("loader"), help: ArgumentHelp(Messages.CLIInterface.loaderFilterHelp.localized), completion: Self.completion(option: "loader")) var optionLoader: String?
    @Option(name: .customLong("category"), help: ArgumentHelp(Messages.CLIInterface.catalogCategoryHelp.localized), completion: Self.completion(option: "category")) var optionCategory: String?
    @Option(name: .customLong("sort"), help: ArgumentHelp(Messages.CLIInterface.catalogSortHelp.localized), completion: Self.completion(option: "sort")) var optionSort: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
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
    static var spec: CommandSpec { CommandSpec(path: ["catalog","show"], summary: Messages.CLIInterface.catalogProjectShowHelp.localized, operands: [
        .init(name: "project", type: "string", required: true, help: Messages.CLIInterface.argumentProject.localized, values: [], role: .text)
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"], defaultValue: "modrinth")
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri catalog show sodium"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentProject: String?
    var operands: [String] { [argumentProject].compactMap { $0 } }
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized), completion: Self.completion(option: "provider")) var optionProvider: String?
    var parameters: [String: Value] { [
        "provider": .text(optionProvider)
    ].filter { $0.value != .null } }
}

struct CatalogVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["catalog","versions"], summary: Messages.CLIInterface.catalogVersionsHelp.localized, operands: [
        .init(name: "project", type: "string", required: true, help: Messages.CLIInterface.argumentProject.localized, values: [], role: .text)
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"], defaultValue: "modrinth"),
        .init(name: "game", type: "string", required: false, help: Messages.CLIInterface.minecraftVersionFilterHelp.localized, values: []),
        .init(name: "loader", type: "string", required: false, help: Messages.CLIInterface.loaderFilterHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri catalog versions sodium --game 1.21.1 --loader fabric"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentProject: String?
    var operands: [String] { [argumentProject].compactMap { $0 } }
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized), completion: Self.completion(option: "provider")) var optionProvider: String?
    @Option(name: .customLong("game"), help: ArgumentHelp(Messages.CLIInterface.minecraftVersionFilterHelp.localized), completion: Self.completion(option: "game")) var optionGame: String?
    @Option(name: .customLong("loader"), help: ArgumentHelp(Messages.CLIInterface.loaderFilterHelp.localized), completion: Self.completion(option: "loader")) var optionLoader: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
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
    static var spec: CommandSpec { CommandSpec(path: ["catalog","categories"], summary: Messages.CLIInterface.catalogCategoriesHelp.localized, operands: [

    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"], defaultValue: "modrinth"),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri catalog categories --provider curseforge"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized), completion: Self.completion(option: "provider")) var optionProvider: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct ContentListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","list"], summary: Messages.CLIInterface.contentListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri content list Survival", "ruri content list Survival --kind shader"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized), completion: Self.completion(option: "kind")) var optionKind: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct ContentImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","import"], summary: Messages.CLIInterface.contentImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentContentFile.localized, values: [], role: .file)
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri content import Survival ~/Downloads/example.jar"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentFile].compactMap { $0 } }
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized), completion: Self.completion(option: "kind")) var optionKind: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","install"], summary: Messages.CLIInterface.contentInstallHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "project", type: "string", required: true, help: Messages.CLIInterface.argumentProject.localized, values: [], role: .text)
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"], defaultValue: "modrinth"),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.contentVersionIdHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri content install Survival sodium --dry-run", "ruri content install Survival sodium"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentProject: String?
    var operands: [String] { [argumentInstance, argumentProject].compactMap { $0 } }
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized), completion: Self.completion(option: "provider")) var optionProvider: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.contentVersionIdHelp.localized), completion: Self.completion(option: "version")) var optionVersion: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized), completion: Self.completion(option: "manual")) var optionManual: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "provider": .text(optionProvider),
        "version": .text(optionVersion),
        "manual": .array(optionManual.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentEnableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","enable"], summary: Messages.CLIInterface.contentEnableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allContentFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri content enable Survival --file example.jar"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized), completion: Self.completion(option: "kind")) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized), completion: Self.completion(option: "file")) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allContentFilesHelp.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentDisableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","disable"], summary: Messages.CLIInterface.contentDisableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allContentFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri content disable Survival --file example.jar"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized), completion: Self.completion(option: "kind")) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized), completion: Self.completion(option: "file")) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allContentFilesHelp.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct ContentRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","remove"], summary: Messages.CLIInterface.contentRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allContentFilesHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri content remove Survival --file example.jar --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized), completion: Self.completion(option: "kind")) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized), completion: Self.completion(option: "file")) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allContentFilesHelp.localized)) var optionAll = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct ContentUpdateCheckCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","update-check"], summary: Messages.CLIInterface.contentCheckUpdatesHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri content update-check Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized), completion: Self.completion(option: "kind")) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized), completion: Self.completion(option: "file")) var optionFile: [String] = []
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string))
    ].filter { $0.value != .null } }
}

struct ContentUpdateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["content","update"], summary: Messages.CLIInterface.contentUpdateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "kind", type: "string", required: false, help: Messages.CLIInterface.contentKindHelp.localized, values: ["mod","resourcepack","shader"], defaultValue: "mod"),
        .init(name: "file", type: "strings", required: false, help: Messages.CLIInterface.contentFileSelectionHelp.localized, values: []),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.updateAllContentFilesHelp.localized, values: []),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri content update Survival --all --dry-run"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("kind"), help: ArgumentHelp(Messages.CLIInterface.contentKindHelp.localized), completion: Self.completion(option: "kind")) var optionKind: String?
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.contentFileSelectionHelp.localized), completion: Self.completion(option: "file")) var optionFile: [String] = []
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.updateAllContentFilesHelp.localized)) var optionAll = false
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized), completion: Self.completion(option: "manual")) var optionManual: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "kind": .text(optionKind),
        "file": .array(optionFile.map(Value.string)),
        "all": .bool(optionAll),
        "manual": .array(optionManual.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","list"], summary: Messages.CLIInterface.worldListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri world list Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct WorldShowCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","show"], summary: Messages.CLIInterface.worldShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "folder", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri world show Survival \"New World\""]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFolder: String?
    var operands: [String] { [argumentInstance, argumentFolder].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct WorldImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","import"], summary: Messages.CLIInterface.worldImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentWorldArchive.localized, values: [], role: .file)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri world import Survival ~/Downloads/World.zip"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentFile].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","export"], summary: Messages.CLIInterface.worldExportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "folder", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentArchiveToCreate.localized, values: [], role: .newFile)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri world export Survival \"New World\" ~/Desktop/World.zip"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFolder: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentFolder, argumentFile].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","remove"], summary: Messages.CLIInterface.worldRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "folder", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri world remove Survival \"New World\" --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFolder: String?
    var operands: [String] { [argumentInstance, argumentFolder].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct WorldBackupCreateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","create"], summary: Messages.CLIInterface.worldBackupCreateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "folder", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text)
    ], options: [
        .init(name: "reason", type: "string", required: false, help: Messages.CLIInterface.worldBackupReasonHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri world backup create Survival \"New World\" --reason \"Before update\""]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFolder: String?
    var operands: [String] { [argumentInstance, argumentFolder].compactMap { $0 } }
    @Option(name: .customLong("reason"), help: ArgumentHelp(Messages.CLIInterface.worldBackupReasonHelp.localized), completion: Self.completion(option: "reason")) var optionReason: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "reason": .text(optionReason),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct WorldBackupListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","list"], summary: Messages.CLIInterface.worldBackupListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri world backup list Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct WorldBackupRestoreCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","restore"], summary: Messages.CLIInterface.worldBackupRestoreHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "backup", type: "string", required: true, help: Messages.CLIInterface.argumentBackup.localized, values: [], role: .text)
    ], options: [
        .init(name: "replace", type: "bool", required: false, help: Messages.CLIInterface.worldBackupReplaceHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri world backup restore Survival <backup> --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentBackup: String?
    var operands: [String] { [argumentInstance, argumentBackup].compactMap { $0 } }
    @Flag(name: .customLong("replace"), help: ArgumentHelp(Messages.CLIInterface.worldBackupReplaceHelp.localized)) var optionReplace = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "replace": .bool(optionReplace),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct WorldBackupRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["world","backup","remove"], summary: Messages.CLIInterface.worldBackupRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "backup", type: "string", required: true, help: Messages.CLIInterface.argumentBackup.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentBackup: String?
    var operands: [String] { [argumentInstance, argumentBackup].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DatapackListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","list"], summary: Messages.CLIInterface.dataPackListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri datapack list Survival \"New World\""]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    var operands: [String] { [argumentInstance, argumentWorld].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackOrderGetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","order","get"], summary: Messages.CLIInterface.dataPackOrderGetHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    var operands: [String] { [argumentInstance, argumentWorld].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct DatapackOrderSetCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","order","set"], summary: Messages.CLIInterface.dataPackOrderSetHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text)
    ], options: [
        .init(name: "key", type: "strings", required: true, help: Messages.CLIInterface.dataPackPriorityListHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    var operands: [String] { [argumentInstance, argumentWorld].compactMap { $0 } }
    @Option(name: .customLong("key"), help: ArgumentHelp(Messages.CLIInterface.dataPackPriorityListHelp.localized), completion: Self.completion(option: "key")) var optionKey: [String] = []
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "key": .array(optionKey.map(Value.string)),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","import"], summary: Messages.CLIInterface.dataPackImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentDataPackFile.localized, values: [], role: .file)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri datapack import Survival \"New World\" ~/Downloads/example.zip"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentWorld, argumentFile].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackEnableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","enable"], summary: Messages.CLIInterface.dataPackEnableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.argumentDataPack.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentName: String?
    var operands: [String] { [argumentInstance, argumentWorld, argumentName].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackDisableCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","disable"], summary: Messages.CLIInterface.dataPackDisableHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.argumentDataPack.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentName: String?
    var operands: [String] { [argumentInstance, argumentWorld, argumentName].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct DatapackRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","remove"], summary: Messages.CLIInterface.dataPackRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.argumentDataPack.localized, values: [], role: .text)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentName: String?
    var operands: [String] { [argumentInstance, argumentWorld, argumentName].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DatapackSearchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","search"], summary: Messages.CLIInterface.dataPackSearchHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "query", type: "string", required: true, help: Messages.CLIInterface.argumentSearchQuery.localized, values: [], role: .text)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri datapack search Survival terralith"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentQuery: String?
    var operands: [String] { [argumentInstance, argumentQuery].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackVersionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","versions"], summary: Messages.CLIInterface.dataPackVersionsHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "project", type: "string", required: true, help: Messages.CLIInterface.argumentProject.localized, values: [], role: .text)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentProject: String?
    var operands: [String] { [argumentInstance, argumentProject].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct DatapackInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["datapack","install"], summary: Messages.CLIInterface.dataPackInstallHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "world", type: "string", required: true, help: Messages.CLIInterface.argumentWorldFolder.localized, values: [], role: .text),
        .init(name: "project", type: "string", required: true, help: Messages.CLIInterface.argumentProject.localized, values: [], role: .text)
    ], options: [
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.dataPackVersionIdHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri datapack install Survival \"New World\" terralith"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentWorld: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentProject: String?
    var operands: [String] { [argumentInstance, argumentWorld, argumentProject].compactMap { $0 } }
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.dataPackVersionIdHelp.localized), completion: Self.completion(option: "version")) var optionVersion: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "version": .text(optionVersion),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","list"], summary: Messages.CLIInterface.schematicListHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "location", type: "string", required: false, help: Messages.CLIInterface.schematicLocationHelp.localized, values: ["schematics","worldedit"], defaultValue: "schematics"),
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.schematicRelativePathHelp.localized, values: []),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri schematic list Survival"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.schematicRelativePathHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    @Option(name: .customLong("location"), help: ArgumentHelp(Messages.CLIInterface.schematicLocationHelp.localized), completion: Self.completion(option: "location")) var optionLocation: String?
    var parameters: [String: Value] { [
        "location": .text(optionLocation),
        "directory": .text(optionDirectory),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct SchematicInfoCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","info"], summary: Messages.CLIInterface.schematicShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentSchematicPath.localized, values: [], role: .text)
    ], options: [
        .init(name: "location", type: "string", required: false, help: Messages.CLIInterface.schematicLocationHelp.localized, values: ["schematics","worldedit"], defaultValue: "schematics")
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri schematic info Survival house.litematic"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentPath: String?
    var operands: [String] { [argumentInstance, argumentPath].compactMap { $0 } }
    @Option(name: .customLong("location"), help: ArgumentHelp(Messages.CLIInterface.schematicLocationHelp.localized), completion: Self.completion(option: "location")) var optionLocation: String?
    var parameters: [String: Value] { [
        "location": .text(optionLocation)
    ].filter { $0.value != .null } }
}

struct SchematicImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","import"], summary: Messages.CLIInterface.schematicImportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentSchematicFile.localized, values: [], role: .file)
    ], options: [
        .init(name: "location", type: "string", required: false, help: Messages.CLIInterface.schematicLocationHelp.localized, values: ["schematics","worldedit"], defaultValue: "schematics"),
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.schematicRelativePathHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri schematic import Survival ~/Downloads/house.litematic"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentFile].compactMap { $0 } }
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.schematicRelativePathHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Option(name: .customLong("location"), help: ArgumentHelp(Messages.CLIInterface.schematicLocationHelp.localized), completion: Self.completion(option: "location")) var optionLocation: String?
    var parameters: [String: Value] { [
        "location": .text(optionLocation),
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicMkdirCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","mkdir"], summary: Messages.CLIInterface.schematicCreateFolderHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.argumentFolderName.localized, values: [], role: .text)
    ], options: [
        .init(name: "location", type: "string", required: false, help: Messages.CLIInterface.schematicLocationHelp.localized, values: ["schematics","worldedit"], defaultValue: "schematics"),
        .init(name: "directory", type: "string", required: false, help: Messages.CLIInterface.schematicParentDirectoryHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri schematic mkdir Survival Builds"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentName: String?
    var operands: [String] { [argumentInstance, argumentName].compactMap { $0 } }
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.schematicParentDirectoryHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Option(name: .customLong("location"), help: ArgumentHelp(Messages.CLIInterface.schematicLocationHelp.localized), completion: Self.completion(option: "location")) var optionLocation: String?
    var parameters: [String: Value] { [
        "location": .text(optionLocation),
        "directory": .text(optionDirectory),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicExportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","export"], summary: Messages.CLIInterface.schematicExportHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentSchematicPath.localized, values: [], role: .text),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentFileToCreate.localized, values: [], role: .newFile)
    ], options: [
        .init(name: "location", type: "string", required: false, help: Messages.CLIInterface.schematicLocationHelp.localized, values: ["schematics","worldedit"], defaultValue: "schematics"),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentPath: String?
    @Argument(help: Self.help(operand: 2), completion: Self.completion(operand: 2)) var argumentFile: String?
    var operands: [String] { [argumentInstance, argumentPath, argumentFile].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Option(name: .customLong("location"), help: ArgumentHelp(Messages.CLIInterface.schematicLocationHelp.localized), completion: Self.completion(option: "location")) var optionLocation: String?
    var parameters: [String: Value] { [
        "location": .text(optionLocation),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct SchematicRemoveCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["schematic","remove"], summary: Messages.CLIInterface.schematicRemoveHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance),
        .init(name: "path", type: "string", required: true, help: Messages.CLIInterface.argumentSchematicPath.localized, values: [], role: .text)
    ], options: [
        .init(name: "location", type: "string", required: false, help: Messages.CLIInterface.schematicLocationHelp.localized, values: ["schematics","worldedit"], defaultValue: "schematics"),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentPath: String?
    var operands: [String] { [argumentInstance, argumentPath].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    @Option(name: .customLong("location"), help: ArgumentHelp(Messages.CLIInterface.schematicLocationHelp.localized), completion: Self.completion(option: "location")) var optionLocation: String?
    var parameters: [String: Value] { [
        "location": .text(optionLocation),
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct InstanceImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["instance","import"], summary: Messages.CLIInterface.instanceImportHelp.localized, operands: [
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentImportArchive.localized, values: [], role: .file)
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceImportDirectoryHelp.localized, values: [], role: .directory),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri instance import ~/Downloads/Pack.mrpack --name Pack --directory default"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentFile: String?
    var operands: [String] { [argumentFile].compactMap { $0 } }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceImportDirectoryHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized), completion: Self.completion(option: "manual")) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackImportCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","import"], summary: Messages.CLIInterface.modpackImportHelp.localized, operands: [
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentModpackArchive.localized, values: [], role: .file)
    ], options: [
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceImportDirectoryHelp.localized, values: [], role: .directory),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri pack import ~/Downloads/Pack.mrpack --name Pack --directory default"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentFile: String?
    var operands: [String] { [argumentFile].compactMap { $0 } }
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceImportDirectoryHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized), completion: Self.completion(option: "manual")) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "name": .text(optionName),
        "directory": .text(optionDirectory),
        "manual": .array(optionManual.map(Value.string)),
        "import-jvm-arguments": .bool(optionImportJvmArguments),
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct PackInstallCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","install"], summary: Messages.CLIInterface.modpackInstallHelp.localized, operands: [
        .init(name: "project", type: "string", required: true, help: Messages.CLIInterface.argumentProject.localized, values: [], role: .text)
    ], options: [
        .init(name: "provider", type: "string", required: false, help: Messages.CLIInterface.contentProviderHelp.localized, values: ["modrinth","curseforge"], defaultValue: "modrinth"),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.contentVersionIdHelp.localized, values: []),
        .init(name: "archive", type: "string", required: false, help: Messages.CLIInterface.manualModpackArchiveHelp.localized, values: [], role: .file),
        .init(name: "name", type: "string", required: true, help: Messages.CLIInterface.newInstanceNameHelp.localized, values: []),
        .init(name: "directory", type: "string", required: true, help: Messages.CLIInterface.instanceImportDirectoryHelp.localized, values: [], role: .directory),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri pack install fabulously-optimized --name \"Fabulously Optimized\" --directory default"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentProject: String?
    var operands: [String] { [argumentProject].compactMap { $0 } }
    @Option(name: .customLong("provider"), help: ArgumentHelp(Messages.CLIInterface.contentProviderHelp.localized), completion: Self.completion(option: "provider")) var optionProvider: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.contentVersionIdHelp.localized), completion: Self.completion(option: "version")) var optionVersion: String?
    @Option(name: .customLong("archive"), help: ArgumentHelp(Messages.CLIInterface.manualModpackArchiveHelp.localized), completion: Self.completion(option: "archive")) var optionArchive: String?
    @Option(name: .customLong("name"), help: ArgumentHelp(Messages.CLIInterface.newInstanceNameHelp.localized), completion: Self.completion(option: "name")) var optionName: String?
    @Option(name: .customLong("directory"), help: ArgumentHelp(Messages.CLIInterface.instanceImportDirectoryHelp.localized), completion: Self.completion(option: "directory")) var optionDirectory: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized), completion: Self.completion(option: "manual")) var optionManual: [String] = []
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
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
    static var spec: CommandSpec { CommandSpec(path: ["pack","show"], summary: Messages.CLIInterface.modpackShowHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri pack show \"Fabulously Optimized\""]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct PackUpdateCheckCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","update-check"], summary: Messages.CLIInterface.modpackVersionsHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri pack update-check \"Fabulously Optimized\""]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct PackUpdateCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["pack","update"], summary: Messages.CLIInterface.modpackUpdateHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "file", type: "string", required: false, help: Messages.CLIInterface.modpackUpdateFileHelp.localized, values: [], role: .file),
        .init(name: "version", type: "string", required: false, help: Messages.CLIInterface.modpackUpdateVersionHelp.localized, values: []),
        .init(name: "archive", type: "string", required: false, help: Messages.CLIInterface.manualModpackUpdateArchiveHelp.localized, values: [], role: .file),
        .init(name: "manual", type: "strings", required: false, help: Messages.CLIInterface.manualCurseForgeFileHelp.localized, values: []),
        .init(name: "replace", type: "bool", required: false, help: Messages.CLIInterface.replaceLocalModificationsHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmLocalModificationsReplacementHelp.localized, values: []),
        .init(name: "import-jvm-arguments", type: "bool", required: false, help: Messages.CLIInterface.importModpackJvmArgumentsHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri pack update \"Fabulously Optimized\" --version <release> --dry-run"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Option(name: .customLong("file"), help: ArgumentHelp(Messages.CLIInterface.modpackUpdateFileHelp.localized), completion: Self.completion(option: "file")) var optionFile: String?
    @Option(name: .customLong("version"), help: ArgumentHelp(Messages.CLIInterface.modpackUpdateVersionHelp.localized), completion: Self.completion(option: "version")) var optionVersion: String?
    @Option(name: .customLong("archive"), help: ArgumentHelp(Messages.CLIInterface.manualModpackUpdateArchiveHelp.localized), completion: Self.completion(option: "archive")) var optionArchive: String?
    @Option(name: .customLong("manual"), help: ArgumentHelp(Messages.CLIInterface.manualCurseForgeFileHelp.localized), completion: Self.completion(option: "manual")) var optionManual: [String] = []
    @Flag(name: .customLong("replace"), help: ArgumentHelp(Messages.CLIInterface.replaceLocalModificationsHelp.localized)) var optionReplace = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmLocalModificationsReplacementHelp.localized)) var optionYes = false
    @Flag(name: .customLong("import-jvm-arguments"), help: ArgumentHelp(Messages.CLIInterface.importModpackJvmArgumentsHelp.localized)) var optionImportJvmArguments = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
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
    static var spec: CommandSpec { CommandSpec(path: ["pack","rollback"], summary: Messages.CLIInterface.modpackRollbackHelp.localized, operands: [
        .init(name: "instance", type: "string", required: true, help: Messages.CLIInterface.argumentInstance.localized, values: [], role: .instance)
    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri pack rollback \"Fabulously Optimized\" --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentInstance: String?
    var operands: [String] { [argumentInstance].compactMap { $0 } }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun),
        "yes": .bool(optionYes)
    ].filter { $0.value != .null } }
}

struct DownloadFetchCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["download","fetch"], summary: Messages.CLIInterface.downloadFetchHelp.localized, operands: [
        .init(name: "url", type: "string", required: true, help: Messages.CLIInterface.argumentDownloadURL.localized, values: [], role: .text),
        .init(name: "file", type: "string", required: true, help: Messages.CLIInterface.argumentDownloadFile.localized, values: [], role: .newFile)
    ], options: [
        .init(name: "sha1", type: "string", required: true, help: Messages.CLIInterface.downloadSha1Help.localized, values: []),
        .init(name: "size", type: "int", required: true, help: Messages.CLIInterface.downloadSizeHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri download fetch https://example.com/example.jar example.jar --sha1 <sha1> --size 1024"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentUrl: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentFile: String?
    var operands: [String] { [argumentUrl, argumentFile].compactMap { $0 } }
    @Option(name: .customLong("sha1"), help: ArgumentHelp(Messages.CLIInterface.downloadSha1Help.localized), completion: Self.completion(option: "sha1")) var optionSha1: String?
    @Option(name: .customLong("size"), help: ArgumentHelp(Messages.CLIInterface.downloadSizeHelp.localized), completion: Self.completion(option: "size")) var optionSize: Int?
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "sha1": .text(optionSha1),
        "size": optionSize.map(Value.integer) ?? .null,
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct RecoveryListCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["recovery","list"], summary: Messages.CLIInterface.recoveryListHelp.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.recoveryInstanceFilterHelp.localized, values: [], role: .instance),
        .init(name: "limit", type: "int", required: false, help: Messages.CLIInterface.resultLimitHelp.localized, values: [], defaultValue: "50", minimum: 1, maximum: 1000),
        .init(name: "offset", type: "int", required: false, help: Messages.CLIInterface.resultOffsetHelp.localized, values: [], defaultValue: "0", minimum: 0),
        .init(name: "all", type: "bool", required: false, help: Messages.CLIInterface.allResultsHelp.localized, values: [])
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri recovery list"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.recoveryInstanceFilterHelp.localized), completion: Self.completion(option: "instance")) var optionInstance: String?
    @Option(name: .customLong("limit"), help: ArgumentHelp(Messages.CLIInterface.resultLimitHelp.localized), completion: Self.completion(option: "limit")) var optionLimit: Int?
    @Option(name: .customLong("offset"), help: ArgumentHelp(Messages.CLIInterface.resultOffsetHelp.localized), completion: Self.completion(option: "offset")) var optionOffset: Int?
    @Flag(name: .customLong("all"), help: ArgumentHelp(Messages.CLIInterface.allResultsHelp.localized)) var optionAll = false
    var parameters: [String: Value] { [
        "instance": .text(optionInstance),
        "limit": optionLimit.map(Value.integer) ?? .null,
        "offset": optionOffset.map(Value.integer) ?? .null,
        "all": .bool(optionAll)
    ].filter { $0.value != .null } }
}

struct RecoveryApplyCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["recovery","apply"], summary: Messages.CLIInterface.recoveryApplyHelp.localized, operands: [
        .init(name: "kind", type: "string", required: true, help: Messages.CLIInterface.argumentRecoveryKind.localized, values: ["instance-copy", "instance-move", "run-directory", "pack-update", "repository-import", "session", "content", "world"], role: .text),
        .init(name: "target", type: "string", required: true, help: Messages.CLIInterface.argumentRecoveryTarget.localized, values: [], role: .recoveryTarget)
    ], options: [
        .init(name: "transaction", type: "string", required: false, help: Messages.CLIInterface.recoveryTransactionHelp.localized, values: []),
        .init(name: "mode", type: "string", required: false, help: Messages.CLIInterface.libraryImportRecoveryModeHelp.localized, values: ["finish","keep-files"]),
        .init(name: "keep-source", type: "bool", required: false, help: Messages.CLIInterface.keepSourceAfterMoveHelp.localized, values: []),
        .init(name: "confirm-game-ended", type: "bool", required: false, help: Messages.CLIInterface.confirmUnmonitoredGameExitHelp.localized, values: []),
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: []),
        .init(name: "yes", type: "bool", required: false, help: Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized, values: [])
    ], mutation: true, confirmation: true, userParticipation: false, examples: ["ruri recovery apply content Survival --yes"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentKind: String?
    @Argument(help: Self.help(operand: 1), completion: Self.completion(operand: 1)) var argumentTarget: String?
    var operands: [String] { [argumentKind, argumentTarget].compactMap { $0 } }
    @Option(name: .customLong("transaction"), help: ArgumentHelp(Messages.CLIInterface.recoveryTransactionHelp.localized), completion: Self.completion(option: "transaction")) var optionTransaction: String?
    @Option(name: .customLong("mode"), help: ArgumentHelp(Messages.CLIInterface.libraryImportRecoveryModeHelp.localized), completion: Self.completion(option: "mode")) var optionMode: String?
    @Flag(name: .customLong("keep-source"), help: ArgumentHelp(Messages.CLIInterface.keepSourceAfterMoveHelp.localized)) var optionKeepSource = false
    @Flag(name: .customLong("confirm-game-ended"), help: ArgumentHelp(Messages.CLIInterface.confirmUnmonitoredGameExitHelp.localized)) var optionConfirmGameEnded = false
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    @Flag(name: .customLong("yes"), help: ArgumentHelp(Messages.CLIInterface.confirmDeleteOrReplaceHelp.localized)) var optionYes = false
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
    static var spec: CommandSpec { CommandSpec(path: ["doctor"], summary: Messages.CLIInterface.doctorCommandHelp.localized, operands: [

    ], options: [
        .init(name: "instance", type: "string", required: false, help: Messages.CLIInterface.doctorInstanceHelp.localized, values: [], role: .instance)
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri doctor", "ruri doctor --instance Survival"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Option(name: .customLong("instance"), help: ArgumentHelp(Messages.CLIInterface.doctorInstanceHelp.localized), completion: Self.completion(option: "instance")) var optionInstance: String?
    var parameters: [String: Value] { [
        "instance": .text(optionInstance)
    ].filter { $0.value != .null } }
}

struct CacheStatusCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cache","status"], summary: Messages.CLIInterface.cacheStatusHelp.localized, operands: [

    ], options: [

    ], mutation: false, confirmation: false, userParticipation: false, examples: []) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    var parameters: [String: Value] { [
        :
    ].filter { $0.value != .null } }
}

struct CacheCleanCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["cache","clean"], summary: Messages.CLIInterface.cacheCleanHelp.localized, operands: [

    ], options: [
        .init(name: "dry-run", type: "bool", required: false, help: Messages.CLIInterface.dryRunHelp.localized, values: [])
    ], mutation: true, confirmation: false, userParticipation: false, examples: ["ruri cache clean --dry-run"]) }
    @OptionGroup var common: CommonOptions
    var operands: [String] { [] }
    @Flag(name: .customLong("dry-run"), help: ArgumentHelp(Messages.CLIInterface.dryRunHelp.localized)) var optionDryRun = false
    var parameters: [String: Value] { [
        "dry-run": .bool(optionDryRun)
    ].filter { $0.value != .null } }
}

struct CompletionsCommand: ExecutableCommand {
    static var spec: CommandSpec { CommandSpec(path: ["completions"], summary: Messages.CLIInterface.completionsHelp.localized, operands: [
        .init(name: "shell", type: "string", required: true, help: Messages.CLIInterface.argumentShell.localized, values: ["zsh", "bash", "fish"])
    ], options: [
    ], mutation: false, confirmation: false, userParticipation: false, examples: ["ruri completions zsh > ~/.zfunc/_ruri", "ruri completions bash > ~/.local/share/bash-completion/completions/ruri", "ruri completions fish > ~/.config/fish/completions/ruri.fish"]) }
    @OptionGroup var common: CommonOptions
    @Argument(help: Self.help(operand: 0), completion: Self.completion(operand: 0)) var argumentShell: String?
    var operands: [String] { [argumentShell].compactMap { $0 } }
    var parameters: [String: Value] { [:] }
}

struct CacheGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "cache", abstract: Messages.CLIInterface.cacheCommands.localized, subcommands: [CacheStatusCommand.self, CacheCleanCommand.self]) }
}

struct AccountServiceKeyGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "service-key", abstract: Messages.CLIInterface.accountServiceKeyCommands.localized, subcommands: [AccountServiceKeyStatusCommand.self, AccountServiceKeySetCommand.self, AccountServiceKeyRemoveCommand.self]) }
}

struct InstanceComponentGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "component", abstract: Messages.CLIInterface.instanceComponentCommands.localized, subcommands: [InstanceComponentListCommand.self, InstanceComponentVersionsCommand.self, InstanceComponentSetCommand.self, InstanceComponentRestoreCommand.self]) }
}

struct DatapackOrderGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "order", abstract: Messages.CLIInterface.dataPackOrderCommands.localized, subcommands: [DatapackOrderGetCommand.self, DatapackOrderSetCommand.self]) }
}

struct DirectoryRunGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "run", abstract: Messages.CLIInterface.instanceRunDirectoryCommands.localized, subcommands: [DirectoryRunGetCommand.self, DirectoryRunSetCommand.self, DirectoryRunRelocateCommand.self]) }
}

struct AccountLoginGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "login", abstract: Messages.CLIInterface.accountLoginCommands.localized, subcommands: [AccountLoginStartCommand.self, AccountLoginCompleteCommand.self, AccountLoginCancelCommand.self]) }
}

struct AppLanguageGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "language", abstract: Messages.CLIInterface.appLanguageCommands.localized, subcommands: [AppLanguageGetCommand.self, AppLanguageSetCommand.self]) }
}

struct WorldBackupGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "backup", abstract: Messages.CLIInterface.worldBackupCommands.localized, subcommands: [WorldBackupCreateCommand.self, WorldBackupListCommand.self, WorldBackupRestoreCommand.self, WorldBackupRemoveCommand.self]) }
}

struct DirectoryGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "directory", abstract: Messages.CLIInterface.directoryCommands.localized, subcommands: [DirectoryListCommand.self, DirectorySelectedCommand.self, DirectoryScanCommand.self, DirectoryAddCommand.self, DirectorySelectCommand.self, DirectoryRefreshCommand.self, DirectoryRemoveCommand.self, DirectoryRenameCommand.self, DirectoryRelocateCommand.self, DirectoryRestoreCommand.self, DirectoryRunGroup.self]) }
}

struct SchematicGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "schematic", abstract: Messages.CLIInterface.schematicCommands.localized, subcommands: [SchematicListCommand.self, SchematicInfoCommand.self, SchematicImportCommand.self, SchematicMkdirCommand.self, SchematicExportCommand.self, SchematicRemoveCommand.self]) }
}

struct InstanceGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "instance", abstract: Messages.CLIInterface.instanceCommands.localized, subcommands: [InstanceListCommand.self, InstanceSelectedCommand.self, InstanceShowCommand.self, InstanceVersionsCommand.self, InstanceCreateCommand.self, InstanceInstallCommand.self, InstanceRepairCommand.self, InstanceSelectCommand.self, InstanceRenameCommand.self, InstanceFavoriteCommand.self, InstanceRemoveCommand.self, InstanceIconCommand.self, InstanceCopyCommand.self, InstanceMoveCommand.self, InstanceExportCommand.self, InstanceComponentGroup.self, InstanceImportCommand.self]) }
}

struct DatapackGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "datapack", abstract: Messages.CLIInterface.dataPackCommands.localized, subcommands: [DatapackListCommand.self, DatapackOrderGroup.self, DatapackImportCommand.self, DatapackEnableCommand.self, DatapackDisableCommand.self, DatapackRemoveCommand.self, DatapackSearchCommand.self, DatapackVersionsCommand.self, DatapackInstallCommand.self]) }
}

struct DownloadGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "download", abstract: Messages.CLIInterface.downloadCommands.localized, subcommands: [DownloadFetchCommand.self]) }
}

struct RecoveryGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "recovery", abstract: Messages.CLIInterface.recoveryCommands.localized, subcommands: [RecoveryListCommand.self, RecoveryApplyCommand.self]) }
}

struct AccountGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "account", abstract: Messages.CLIInterface.accountCommands.localized, subcommands: [AccountListCommand.self, AccountSelectedCommand.self, AccountShowCommand.self, AccountAddOfflineCommand.self, AccountSelectCommand.self, AccountRefreshCommand.self, AccountRemoveCommand.self, AccountLogoutCommand.self, AccountLoginGroup.self, AccountServiceKeyGroup.self]) }
}

struct SessionGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "session", abstract: Messages.CLIInterface.sessionCommands.localized, subcommands: [SessionListCommand.self, SessionShowCommand.self, SessionWaitCommand.self, SessionQuitCommand.self, SessionStopCommand.self, SessionLogsCommand.self, SessionDiagnoseCommand.self, SessionExportCommand.self]) }
}

struct CatalogGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "catalog", abstract: Messages.CLIInterface.catalogCommands.localized, subcommands: [CatalogSearchCommand.self, CatalogShowCommand.self, CatalogVersionsCommand.self, CatalogCategoriesCommand.self]) }
}

struct ContentGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "content", abstract: Messages.CLIInterface.contentCommands.localized, subcommands: [ContentListCommand.self, ContentImportCommand.self, ContentInstallCommand.self, ContentEnableCommand.self, ContentDisableCommand.self, ContentRemoveCommand.self, ContentUpdateCheckCommand.self, ContentUpdateCommand.self]) }
}

struct ConfigGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "config", abstract: Messages.CLIInterface.configCommands.localized, subcommands: [ConfigGetCommand.self, ConfigSetCommand.self, ConfigApplyCommand.self, ConfigResetCommand.self, ConfigInheritCommand.self, ConfigFieldsCommand.self]) }
}

struct LaunchGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "launch", abstract: Messages.CLIInterface.launchCommands.localized, subcommands: [LaunchPreflightCommand.self, LaunchStartCommand.self]) }
}

struct WorldGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "world", abstract: Messages.CLIInterface.worldCommands.localized, subcommands: [WorldListCommand.self, WorldShowCommand.self, WorldImportCommand.self, WorldExportCommand.self, WorldRemoveCommand.self, WorldBackupGroup.self]) }
}

struct JavaGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "java", abstract: Messages.CLIInterface.javaCommands.localized, subcommands: [JavaListCommand.self, JavaAvailableCommand.self, JavaAddCommand.self, JavaForgetCommand.self, JavaDefaultCommand.self, JavaReferencesCommand.self, JavaInstallCommand.self, JavaRepairCommand.self, JavaRemoveCommand.self]) }
}

struct PackGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "pack", abstract: Messages.CLIInterface.modpackCommands.localized, subcommands: [PackImportCommand.self, PackInstallCommand.self, PackShowCommand.self, PackUpdateCheckCommand.self, PackUpdateCommand.self, PackRollbackCommand.self]) }
}

struct AppGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "app", abstract: Messages.CLIInterface.appCommands.localized, subcommands: [AppInfoCommand.self, AppLanguageGroup.self]) }
}

struct CliGroup: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "cli", abstract: Messages.CLIInterface.cliCommands.localized, subcommands: [CliStatusCommand.self, CliInstallCommand.self, CliUninstallCommand.self]) }
}

struct RuriCommand: ParsableCommand {
    // Global options are accepted here too, so shell completion can skip them.
    @OptionGroup var common: CommonOptions
    // Ordered as the root help groups them.
    static var configuration: CommandConfiguration { CommandConfiguration(commandName: "ruri", abstract: Messages.CLIInterface.rootCommandHelp.localized, version: BuildConfiguration().version, subcommands: [LaunchGroup.self, SessionGroup.self, ServerGroup.self, InstanceGroup.self, DirectoryGroup.self, JavaGroup.self, AccountGroup.self, CatalogGroup.self, ContentGroup.self, PackGroup.self, DownloadGroup.self, WorldGroup.self, DatapackGroup.self, SchematicGroup.self, ConfigGroup.self, AppGroup.self, CliGroup.self, CompletionsCommand.self, DoctorCommand.self, RecoveryGroup.self, CacheGroup.self, SchemaCommand.self]) }
}

enum CommandRegistry {
    static var commands: [CommandSpec] { [SchemaCommand.spec, AppInfoCommand.spec, AppLanguageGetCommand.spec, AppLanguageSetCommand.spec, CliStatusCommand.spec, CliInstallCommand.spec, CliUninstallCommand.spec, ConfigGetCommand.spec, ConfigSetCommand.spec, ConfigApplyCommand.spec, ConfigResetCommand.spec, ConfigInheritCommand.spec, ConfigFieldsCommand.spec, InstanceListCommand.spec, InstanceSelectedCommand.spec, InstanceShowCommand.spec, InstanceVersionsCommand.spec, InstanceCreateCommand.spec, InstanceInstallCommand.spec, InstanceRepairCommand.spec, InstanceSelectCommand.spec, InstanceRenameCommand.spec, InstanceFavoriteCommand.spec, InstanceRemoveCommand.spec, InstanceIconCommand.spec, InstanceCopyCommand.spec, InstanceMoveCommand.spec, InstanceExportCommand.spec, InstanceComponentListCommand.spec, InstanceComponentVersionsCommand.spec, InstanceComponentSetCommand.spec, InstanceComponentRestoreCommand.spec, DirectoryListCommand.spec, DirectorySelectedCommand.spec, DirectoryScanCommand.spec, DirectoryAddCommand.spec, DirectorySelectCommand.spec, DirectoryRefreshCommand.spec, DirectoryRemoveCommand.spec, DirectoryRenameCommand.spec, DirectoryRelocateCommand.spec, DirectoryRestoreCommand.spec, DirectoryRunGetCommand.spec, DirectoryRunSetCommand.spec, DirectoryRunRelocateCommand.spec, JavaListCommand.spec, JavaAvailableCommand.spec, JavaAddCommand.spec, JavaForgetCommand.spec, JavaDefaultCommand.spec, JavaReferencesCommand.spec, JavaInstallCommand.spec, JavaRepairCommand.spec, JavaRemoveCommand.spec, AccountListCommand.spec, AccountSelectedCommand.spec, AccountShowCommand.spec, AccountAddOfflineCommand.spec, AccountSelectCommand.spec, AccountRefreshCommand.spec, AccountRemoveCommand.spec, AccountLogoutCommand.spec, AccountLoginStartCommand.spec, AccountLoginCompleteCommand.spec, AccountLoginCancelCommand.spec, AccountServiceKeyStatusCommand.spec, AccountServiceKeySetCommand.spec, AccountServiceKeyRemoveCommand.spec, LaunchPreflightCommand.spec, LaunchStartCommand.spec, ServerListCommand.spec, ServerAddCommand.spec, ServerEditCommand.spec, ServerRemoveCommand.spec, ServerMoveCommand.spec, ServerFavoriteCommand.spec, ServerPreferencesCommand.spec, ServerQueryCommand.spec, SessionListCommand.spec, SessionShowCommand.spec, SessionWaitCommand.spec, SessionQuitCommand.spec, SessionStopCommand.spec, SessionLogsCommand.spec, SessionDiagnoseCommand.spec, SessionExportCommand.spec, CatalogSearchCommand.spec, CatalogShowCommand.spec, CatalogVersionsCommand.spec, CatalogCategoriesCommand.spec, ContentListCommand.spec, ContentImportCommand.spec, ContentInstallCommand.spec, ContentEnableCommand.spec, ContentDisableCommand.spec, ContentRemoveCommand.spec, ContentUpdateCheckCommand.spec, ContentUpdateCommand.spec, WorldListCommand.spec, WorldShowCommand.spec, WorldImportCommand.spec, WorldExportCommand.spec, WorldRemoveCommand.spec, WorldBackupCreateCommand.spec, WorldBackupListCommand.spec, WorldBackupRestoreCommand.spec, WorldBackupRemoveCommand.spec, DatapackListCommand.spec, DatapackOrderGetCommand.spec, DatapackOrderSetCommand.spec, DatapackImportCommand.spec, DatapackEnableCommand.spec, DatapackDisableCommand.spec, DatapackRemoveCommand.spec, DatapackSearchCommand.spec, DatapackVersionsCommand.spec, DatapackInstallCommand.spec, SchematicListCommand.spec, SchematicInfoCommand.spec, SchematicImportCommand.spec, SchematicMkdirCommand.spec, SchematicExportCommand.spec, SchematicRemoveCommand.spec, InstanceImportCommand.spec, PackImportCommand.spec, PackInstallCommand.spec, PackShowCommand.spec, PackUpdateCheckCommand.spec, PackUpdateCommand.spec, PackRollbackCommand.spec, DownloadFetchCommand.spec, CacheStatusCommand.spec, CacheCleanCommand.spec, RecoveryListCommand.spec, RecoveryApplyCommand.spec, DoctorCommand.spec, CompletionsCommand.spec] }
}

