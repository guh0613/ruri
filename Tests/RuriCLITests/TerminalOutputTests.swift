import ArgumentParser
import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore
import RuriLocalization

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
}

@MainActor struct TerminalOutputTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = InstanceService(paths: LauncherPaths(root: root))
        for name in ["Survival", "My World", "生存 世界"] {
            _ = try service.create(name: name, game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        }
        try StateStore.update(LauncherPaths(root: root)) { state in
            if let index = state.instances.firstIndex(where: { $0.name == "Survival" }) { state.instances[index].installed = true; state.instances[index].favorite = true }
        }
        return root
    }

    private func profile(width: Int = 80, terminal: Bool = false, environment: [String: String] = [:]) -> TerminalProfile {
        TerminalProfile(output: .init(isTerminal: terminal, width: width), error: .init(isTerminal: terminal, width: width), environment: environment)
    }

    private func run(_ arguments: [String], _ root: URL, profile: TerminalProfile = .pipe) async -> (status: Int32, output: String, errors: String) {
        let capture = CommandCapture()
        let status = await CLIApplication.run(arguments + ["--data-dir", root.path], write: capture.write, terminal: profile)
        return (status, String(decoding: capture.output, as: UTF8.self), String(decoding: capture.errors, as: UTF8.self))
    }

    private func request(_ arguments: [String]) throws -> CommandRequest {
        try #require(try RuriCommand.parseAsRoot(arguments) as? any ExecutableCommand).request
    }

    /// Output created outside the CLI entry point, in its default language.
    private func sink(_ capture: CommandCapture, quiet: Bool = false, details: Bool = false, terminal: TerminalProfile = .pipe, clock: @escaping @Sendable () -> Date = { Date() }) -> CommandOutput {
        LocalizationContext.$current.withValue(.commandLine()) {
            CommandOutput(format: .text, quiet: quiet, details: details, write: capture.write, terminal: terminal, clock: clock)
        }
    }

    @Test func colorFollowsTheExplicitModeThenNoColorThenTheStream() async throws {
        let terminal = TerminalProfile.Stream(isTerminal: true, width: 80), pipe = TerminalProfile.Stream(isTerminal: false, width: 80)
        #expect(profile(environment: ["TERM": "xterm-256color"]).colors(terminal, mode: "auto"))
        #expect(!profile(environment: ["TERM": "xterm-256color", "NO_COLOR": "1"]).colors(terminal, mode: "auto"))
        #expect(profile(environment: ["NO_COLOR": "1"]).colors(pipe, mode: "always"))
        #expect(!profile(environment: ["TERM": "xterm-256color"]).colors(terminal, mode: "never"))
        #expect(!profile(environment: ["TERM": "xterm-256color"]).colors(pipe, mode: "auto"))
        #expect(!profile(environment: ["TERM": "dumb"]).colors(terminal, mode: "auto"))

        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await run(["instance", "list", "--color", "always"], root).output.contains("\u{1B}["))
        #expect(!(await run(["instance", "list"], root).output.contains("\u{1B}")))
        let error = await run(["instance", "show", "Nothing", "--color", "always"], root)
        #expect(error.errors.contains("\u{1B}[31m"))
        // Presentation options never change structured output.
        let plain = await run(["instance", "list", "--json"], root)
        for extra in [["--color", "always"], ["--details"], ["--color=always", "--details"]] {
            #expect(await run(["instance", "list", "--json"] + extra, root).output == plain.output)
        }
        let stream = await run(["instance", "show", "Nothing", "--output", "ndjson", "--color", "always", "--details"], root)
        #expect(!stream.output.contains("\u{1B}") && stream.errors.isEmpty)
        #expect(await run(["instance", "list", "--color", "sometimes"], root).status == 2)
    }

    @Test func listsShowShortIDsThatResolveAndDetailsShowFullIDs() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = try TargetCatalog(paths: LauncherPaths(root: root)).index(.instance)
        let compact = await run(["instance", "list"], root).output
        let detailed = await run(["instance", "list", "--details"], root).output
        for entry in index.entries {
            #expect(compact.contains(index.shortID(entry.id)) && !compact.contains(entry.id.uuidString))
            #expect(detailed.contains(entry.id.uuidString))
            #expect(await run(["instance", "show", index.shortID(entry.id), "--json"], root).output.contains(entry.id.uuidString))
        }
        #expect(compact.contains("Survival ★") && compact.contains("Installed") && compact.contains("Not installed"))
        #expect(compact.hasSuffix("Total: 3.\n"))
        // Short IDs come from every instance, not only the page shown.
        let page = await run(["instance", "list", "--limit", "1", "--offset", "1"], root).output
        #expect(page.contains("Showing 2–2 of 3.") && page.contains("Next page: ruri instance list --limit 1 --offset 2 --data-dir"))
    }

    @Test func layoutFitsTheMeasuredWidthWithoutShorteningIDsOrPaths() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for width in [40, 80, 120] {
            let terminal = profile(width: width, terminal: true)
            for arguments in [["instance", "list"], ["instance", "list", "--details"], ["instance", "show", "My World"], ["instance", "show", "生存 世界", "--details"],
                              ["config", "get", "--scope", "defaults"], ["config", "set", "memory.maximumMB", "6144", "--scope", "instance:Survival", "--dry-run"], ["launch", "preflight", "My World"]] {
                let result = await run(arguments, root, profile: terminal)
                let text = result.output + result.errors
                #expect(!text.contains("…"), "\(width) \(arguments)")
                for line in text.split(separator: "\n").map(String.init) where TerminalText.width(line) > width {
                    // Only words that must stay whole, such as paths and commands, may overflow.
                    let words = line.trimmingCharacters(in: .whitespaces)
                    #expect(!words.contains(" ") || line.contains("/") || line.contains("ruri "), "\(width) \(arguments): \(line)")
                }
                #expect(text.contains(root.path) || !arguments.contains("--details") || arguments.first == "config", "\(width) \(arguments)")
            }
            // Narrow terminals drop the least important columns first and say so.
            let list = await run(["instance", "list"], root, profile: terminal).output
            #expect(list.hasPrefix("Name"))
            #expect(list.contains("Components") == (width >= 80) && list.contains("Status") == (width >= 80), "\(width): \(list)")
            #expect(list.contains("Some columns are hidden") == (width < 80), "\(width): \(list)")
            // --details shows every column, or every value in blocks.
            let detailed = await run(["instance", "list", "--details"], root, profile: terminal).output
            #expect(!detailed.contains("Some columns are hidden") && detailed.contains(root.path), "\(width): \(detailed)")
        }
        // Too narrow for a table, entries become blocks that keep every value.
        let narrow = await run(["instance", "list", "--details"], root, profile: profile(width: 40, terminal: true)).output
        #expect(narrow.contains("\n  ID") && narrow.contains(root.path))
    }

    @Test func progressIsRewrittenOnTerminalsAndThrottledInPipes() throws {
        let clock = TestClock()
        let pipe = CommandCapture()
        let piped = sink(pipe, clock: { clock.now })
        piped.event("progress", .object(["stage": .string("Downloading libraries"), "completed": .integer(0), "total": .integer(40)]))
        for completed in 1...9 { clock.advance(1); piped.event("progress", .object(["stage": .string("Downloading libraries"), "completed": .integer(completed), "total": .integer(40)])) }
        clock.advance(2); piped.event("progress", .object(["stage": .string("Downloading libraries"), "completed": .integer(12), "total": .integer(40)]))
        clock.advance(1); piped.event("progress", .object(["stage": .string("Downloading libraries"), "completed": .integer(40), "total": .integer(40)]))
        piped.event("progress", .object(["stage": .string("Preparing"), "completed": .integer(0), "total": .integer(0)]))
        clock.advance(12); piped.event("progress", .object(["stage": .string("Preparing"), "completed": .integer(0), "total": .integer(0)]))
        piped.event("progress", .object(["phase": .string("copying"), "bytesCopied": .integer(1_000_000), "totalBytes": .integer(4_000_000)]))
        piped.result(.object(["id": .string("done")]))
        let lines = String(decoding: pipe.errors, as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(lines == ["Downloading libraries 0/40", "Downloading libraries 12/40", "Downloading libraries 40/40", "Preparing", "Preparing 12s", "Copying 1 MB of 4 MB (25%)"], "\(lines)")
        #expect(!String(decoding: pipe.errors, as: UTF8.self).contains("\r"))

        let tty = CommandCapture()
        let terminal = sink(tty, terminal: profile(width: 30, terminal: true), clock: { clock.now })
        for completed in 0...100 { terminal.event("progress", .object(["stage": .string("Downloading the game files"), "completed": .integer(completed), "total": .integer(100)])) }
        terminal.result(.object(["id": .string("done")]))
        let written = String(decoding: tty.errors, as: UTF8.self)
        #expect(written.hasPrefix("\r\u{1B}[2K") && written.hasSuffix("\r\u{1B}[2K") && !written.contains("\n"))
        // Lines are cut to the width so the terminal can rewrite them.
        #expect(written.components(separatedBy: "\r\u{1B}[2K").allSatisfy { TerminalText.width($0) < 30 })

        let quiet = CommandCapture()
        let silent = sink(quiet, quiet: true, clock: { clock.now })
        silent.event("progress", .object(["stage": .string("Downloading"), "completed": .integer(1), "total": .integer(2)]))
        silent.result(.object(["id": .string("done")]), warnings: ["Still visible"])
        #expect(String(decoding: quiet.errors, as: UTF8.self) == "Warning: Still visible\n")
    }

    @Test func errorsSayWhatHappenedWhichTargetAndHowToContinue() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(StateStore.load(LauncherPaths(root: root)).instances.first { $0.name == "My World" }?.id)
        let short = try TargetCatalog(paths: LauncherPaths(root: root)).index(.instance).shortID(id)
        let failure = await run(["launch", "preflight", "My World"], root)
        #expect(failure.status == 1 && failure.output.isEmpty)
        let lines = failure.errors.split(separator: "\n").map(String.init)
        #expect(lines.first == "Error [INSTALLATION_REQUIRED]: Install this instance before launching.")
        #expect(lines.contains("  Instance  My World (\(short))"))
        #expect(lines.last == "Next: ruri instance install \(id.uuidString) --data-dir \(CommandTextRenderer.shell([root.path]))")
        // Structured next actions are unchanged.
        let json = await run(["launch", "preflight", "My World", "--json"], root)
        #expect(json.output.contains(#""command":["instance","install","\#(id.uuidString)"]"#))

        let capture = CommandCapture(), moved = sink(capture)
        moved.setRequest(try request(["instance", "move", id.uuidString, "--directory", "default", "--data-dir", "/tmp/data dir"]))
        moved.result(error: .init("IO_ERROR", "Copy failed.", nextActions: [.init(["recovery", "list", "--instance", id.uuidString, "--json"])],
            details: .object(["recovery": .array([.object(["kind": .string("instance-move"), "target": .string(id.uuidString)])]),
                              "preservedFiles": .array([.string("/tmp/kept files/world")]), "messageID": .string("Core.copyFailed")])))
        let text = String(decoding: capture.errors, as: UTF8.self)
        #expect(text.contains("Pending recovery:\n  instance-move"))
        #expect(text.contains("Preserved files:\n  /tmp/kept files/world"))
        #expect(text.contains("Next: ruri recovery list --instance \(id.uuidString) --data-dir '/tmp/data dir'"))
        #expect(!text.contains("--json") && !text.contains("Core.copyFailed") && text.contains("--details"))
        let detailed = CommandCapture(), verbose = sink(detailed, details: true)
        verbose.result(error: .init("IO_ERROR", "Copy failed.", details: .object(["messageID": .string("Core.copyFailed")])))
        #expect(String(decoding: detailed.errors, as: UTF8.self).contains("Core.copyFailed"))
    }

    @Test func emptyListsTellNothingFromNoMatchesAndPastTheEnd() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: empty) }
        let none = await run(["instance", "list"], empty).output
        #expect(none == "There is nothing here yet.\nNext: ruri instance create --help --data-dir \(CommandTextRenderer.shell([empty.path]))\n")
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let filtered = await run(["instance", "list", "--name", "Nope"], root).output
        #expect(filtered.hasPrefix("Nothing matches these filters.\nWithout filters: ruri instance list --data-dir"))
        #expect(await run(["instance", "list", "--offset", "10"], root).output.hasPrefix("Nothing at this offset; there are 3 results in total."))
    }

    @Test func launchResultsLeadWithTheOutcome() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try #require(StateStore.load(LauncherPaths(root: root)).instances.first { $0.name == "Survival" }?.id)
        let checked = CommandCapture(), preflight = sink(checked)
        preflight.setRequest(try request(["launch", "preflight", id.uuidString, "--world", "New World", "--data-dir", root.path]))
        let plan: Value = .object(["instanceID": .string(id.uuidString), "accountID": .string(UUID().uuidString), "accountKind": .string("offline"),
            "javaPath": .string("/Library/Java/21/bin/java"), "javaMajor": .integer(21), "gameDirectory": .string("/games/Survival"),
            "command": .string("java -Xmx4G net.minecraft.client.main.Main"), "jvmTuning": .null, "authenticationChecked": .bool(true), "environmentNames": .array([])])
        preflight.result(plan)
        let text = String(decoding: checked.output, as: UTF8.self)
        #expect(text.hasPrefix("Ready to launch Survival ("))
        #expect(text.contains("21 · /Library/Java/21/bin/java") && !text.contains("net.minecraft"))
        #expect(text.contains("Next: ruri launch start \(id.uuidString) --world 'New World' --data-dir"))

        let started = CommandCapture(), start = sink(started)
        start.setRequest(try request(["launch", "start", id.uuidString, "--data-dir", root.path]))
        let session = UUID().uuidString
        start.result(.object(["id": .string(session), "instanceID": .string(id.uuidString), "instanceName": .string("Survival"), "state": .string("running"),
            "stage": .string("running"), "createdAt": .string("2026-10-20T08:00:00Z"), "finished": .bool(false), "playedSeconds": .number(0), "gameExitCode": .null,
            "segments": .array([]), "trackingVersion": .null, "failure": .null, "activity": .string("monitoring")]))
        let launched = String(decoding: started.output, as: UTF8.self)
        #expect(launched.hasPrefix("Started Survival ("))
        #expect(launched.contains("Next: ruri session wait \(id.uuidString) \(session) --data-dir"))
    }

    @Test func chineseOutputTranslatesLabelsButNotValues() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let english = await run(["instance", "list"], root).output
        let chinese = await run(["instance", "list", "--language", "zh-Hans"], root).output
        #expect(english.hasPrefix("Name") && chinese.hasPrefix("名称"))
        #expect(chinese.contains("1.21.1") && chinese.contains("Survival"))
        let index = try TargetCatalog(paths: LauncherPaths(root: root)).index(.instance)
        for entry in index.entries { #expect(chinese.contains(index.shortID(entry.id))) }
    }
}
