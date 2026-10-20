import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore
import RuriLocalization

@MainActor struct HelpCommandTests {
    private func run(_ arguments: [String]) async -> (Int32, String, String) {
        let output = CommandCapture()
        let status = await CLIApplication.run(arguments, write: output.write)
        return (status, String(decoding: output.output, as: UTF8.self), String(decoding: output.errors, as: UTF8.self))
    }

    @Test func rootAndNestedHelpPreserveTheRequestedCommandContext() async throws {
        let cases: [([String], String)] = [
            ([], "ruri <command>"), (["--help"], "ruri <command>"), (["-h"], "ruri <command>"), (["help"], "ruri <command>"),
            (["--help", "app"], "ruri app <subcommand>"), (["app", "--help"], "ruri app <subcommand>"),
            (["-h", "app"], "ruri app <subcommand>"), (["--quiet", "--help", "app"], "ruri app <subcommand>"),
            (["help", "app"], "ruri app <subcommand>"), (["app"], "ruri app <subcommand>"),
            (["app", "language"], "ruri app language <subcommand>"), (["--json", "app"], "ruri app <subcommand>"),
            (["help", "app", "language"], "ruri app language <subcommand>"),
            (["--help", "world", "backup", "restore"], "ruri world backup restore <instance> <backup> --yes"),
            (["world", "backup", "restore", "-h"], "ruri world backup restore <instance> <backup> --yes"),
            (["world", "--help", "backup", "restore"], "ruri world backup restore <instance> <backup> --yes")
        ]
        for (arguments, usage) in cases {
            let (status, help, errors) = await run(arguments)
            #expect(status == 0)
            #expect(help.contains("Usage: " + usage + " "), "\(arguments): \(help)")
            #expect(errors.isEmpty)
        }
    }

    @Test func everyPublicCommandShowsItsArgumentsAndOptionsWithoutExecuting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("state.json"), original = Data("invalid state".utf8)
        try original.write(to: state)
        for spec in CommandRegistry.commands {
            let (status, help, errors) = await run(["--data-dir", root.path] + spec.path + ["--help"])
            #expect(status == 0, "\(spec.path): \(help)")
            #expect(!help.hasPrefix("Usage"))
            #expect(help.contains("Usage: ruri " + spec.path.joined(separator: " ")))
            for option in spec.options { #expect(help.contains("--" + option.name), "\(spec.path): \(option.name)") }
            for operand in spec.operands {
                #expect(help.contains("<\(operand.name)>  "), "\(spec.path): \(operand.name)")
                #expect(!operand.help.isEmpty && operand.help != operand.name, "\(spec.path): \(operand.name)")
            }
            for example in spec.examples { #expect(help.contains(example)) }
            #expect(help.contains("--json"))
            #expect(errors.isEmpty)
        }
        #expect(try Data(contentsOf: state) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["state.json"])
    }

    @Test func navigationIsShortAndGroupedByPurpose() async throws {
        let (_, root, _) = await run(["--help"])
        #expect(root.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).count <= 28, "\(root)")
        #expect(root.split(separator: "\n").allSatisfy { TerminalText.width(String($0)) <= 80 })
        let listed = Set(CommandHelp.sections.flatMap { $0.commands })
        let commands = RuriCommand.configuration.subcommands.compactMap { $0.configuration.commandName }
        #expect(listed == Set(commands) && listed.count == commands.count)
        for command in commands { #expect(root.contains(" " + command + " ")) }
        #expect(!root.contains("instance commands"))
        let (_, group, _) = await run(["instance"])
        #expect(group.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).count <= 32, "\(group)")
        #expect(!group.contains("--component") && !group.contains("Examples:"))
        for child in InstanceGroup.configuration.subcommands { #expect(group.contains("  " + (child.configuration.commandName ?? ""))) }
    }

    @Test func helpWrapsToTheMeasuredWidth() async throws {
        for width in [40, 80, 120] {
            let profile = TerminalProfile(output: .init(isTerminal: true, width: width), error: .init(isTerminal: true, width: width), environment: [:])
            let output = CommandCapture()
            for arguments in [["instance", "create", "--help"], ["--help"], ["instance"], ["help", "--all"]] {
            #expect(await CLIApplication.run(arguments, write: output.write, terminal: profile) == 0)
            }
            let lines = String(decoding: output.output, as: UTF8.self).split(separator: "\n").map(String.init)
            // Only unbreakable words, such as usage and examples, may exceed the width.
            for line in lines where TerminalText.width(line) > width { #expect(!line.contains(" ") || line.hasPrefix("ruri ") || line.hasPrefix("  ruri ") || line.hasPrefix("Usage: "), "\(width): \(line)") }
        }
        #expect(TerminalText.width("实例 Survival") == 13)
        #expect(TerminalText.width("\u{1B}[1mbold\u{1B}[0m") == 4)
        #expect(TerminalText.width("e\u{301}") == 1)
        #expect(TerminalText.width("🧱") == 2)
        #expect(TerminalText.wrap("目标可以是区分大小写的完整名称", width: 10).allSatisfy { TerminalText.width($0) <= 10 })
    }

    @Test func completeHelpExpandsTheSubtreeAndStatesRulesOnce() async throws {
        let (status, text, _) = await run(["help", "instance", "--full"])
        #expect(status == 0)
        for spec in CommandRegistry.commands where spec.path.first == "instance" {
            #expect(text.contains(CommandHelp.signature(spec)))
            for option in spec.options { #expect(text.contains("--" + option.name)) }
            for example in spec.examples { #expect(text.contains(example)) }
        }
        #expect(!text.contains("ruri account add-offline"))
        let note = String(LocalizationContext.commandLine().string(Messages.CLIExperience.noteTargets).prefix(30))
        #expect(text.components(separatedBy: note).count == 2)
        #expect(text.components(separatedBy: "Global options:").count == 2)
        #expect(await run(["help", "instance", "--full", "--all"]).0 == 2)
        let json = CommandCapture()
        #expect(await CLIApplication.run(["help", "instance", "--full", "--json"], write: json.write) == 0)
        #expect(try json.value["data"].string?.contains("ruri instance create") == true)
    }

    @Test func globalOptionsWorkBeforeBetweenAndAfterCommandNames() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try InstanceService(paths: LauncherPaths(root: root)).create(name: "Placed", game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        var results: Set<Data> = []
        for arguments in [["--json", "--data-dir", root.path, "instance", "list"], ["instance", "--json", "--data-dir=" + root.path, "list"],
                          ["instance", "list", "--data-dir", root.path, "--json"], ["--data-dir=" + root.path, "instance", "--output", "json", "list"]] {
            let output = CommandCapture()
            #expect(await CLIApplication.run(arguments, write: output.write) == 0, "\(arguments)")
            #expect(try output.value["data"]["total"] == .integer(1))
            results.insert(output.output)
        }
        #expect(results.count == 1)
        // After --, an option-shaped word is an operand, not a setting.
        let id = try #require(StateStore.load(LauncherPaths(root: root)).instances.first?.id.uuidString)
        let literal = await run(["instance", "rename", id, "--dry-run", "--data-dir", root.path, "--", "--json"])
        #expect(literal.0 == 0)
        #expect((try? JSONDecoder().decode(Value.self, from: Data(literal.1.utf8))) == nil)
        #expect(literal.1.contains("--json"))
        #expect(await run(["schema", "--json", "--", "--help"]).0 == 1)
    }

    @Test func mistakesShowTheLocalUsageAndASuggestionWithoutRunning() async throws {
        let cases: [([String], String, String)] = [
            (["instnace", "list"], "“instance”", "Usage: ruri <command>"),
            (["instance", "lst"], "“list”", "Usage: ruri instance <subcommand>"),
            (["instance", "list", "--limt", "5"], "“--limit”", "Usage: ruri instance list [options]"),
            (["instance", "rename"], "<instance> <name>", "Usage: ruri instance rename <instance> <name>"),
            (["instance", "rename", "a", "b", "c"], "“c”", "Usage: ruri instance rename"),
            (["instance", "create", "--name"], "--name", "Usage: ruri instance create")
        ]
        for (arguments, detail, usage) in cases {
            let (status, output, errors) = await run(arguments)
            #expect(status == 2, "\(arguments)")
            #expect(output.isEmpty)
            #expect(errors.contains("INVALID_ARGUMENT") && errors.contains(detail) && errors.contains(usage), "\(arguments): \(errors)")
            #expect(errors.contains((["Next: ruri help"] + CommandHelp.prefix(in: arguments)).joined(separator: " ")))
        }
        let json = CommandCapture()
        #expect(await CLIApplication.run(["instance", "lst", "--json"], write: json.write) == 2)
        #expect(try json.value["error"]["code"] == .string("INVALID_ARGUMENT"))
        #expect(try json.value["error"]["nextActions"].decode([Value].self).first?["command"] == .array([.string("help"), .string("instance")]))
    }

    @Test func completionScriptsAreScriptsNotHelp() async throws {
        for shell in ["zsh", "bash", "fish"] {
            let generated = await run(["--generate-completion-script", shell])
            #expect(generated.0 == 0)
            #expect(!generated.1.contains("Usage:") && generated.1.contains("ruri"))
            let command = await run(["completions", shell])
            #expect(command.0 == 0)
            #expect(command.1 == generated.1)
            let json = CommandCapture()
            #expect(await CLIApplication.run(["completions", shell, "--json"], write: json.write) == 0)
            #expect(try json.value["data"]["script"].string?.trimmingCharacters(in: .newlines) == command.1.trimmingCharacters(in: .newlines))
        }
        #expect(await run(["completions", "zsh"]).1.hasPrefix("#compdef ruri"))
        #expect(await run(["completions", "tcsh"]).0 == 2)
    }

    @Test func versionPrintsTextInEveryFormat() async throws {
        let plain = await run(["--version"]), json = await run(["--version", "--json"])
        #expect(plain.0 == 0 && !plain.1.isEmpty && plain.1 == json.1)
    }
}
