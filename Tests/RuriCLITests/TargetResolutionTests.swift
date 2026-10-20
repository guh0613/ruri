import ArgumentParser
import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore

@MainActor struct TargetResolutionTests {
    private struct Fixture {
        let root: URL
        var paths: LauncherPaths { LauncherPaths(root: root) }
        var ids: [String: UUID] = [:]
    }

    // Two instances share an eight-character ID prefix, one instance is named
    // like another's ID prefix, and two instances share a name.
    private static let creative = UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000001")!
    private static let world = UUID(uuidString: "1A2B3C4D-1000-4000-8000-000000000002")!
    private static let chinese = UUID(uuidString: "DEADBEEF-2000-4000-8000-000000000003")!

    private func fixture() throws -> Fixture {
        var fixture = Fixture(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let service = InstanceService(paths: fixture.paths)
        for name in ["Survival", "Survival", "Creative", "My World", "生存 世界", "deadbeef"] {
            _ = try service.create(name: name, game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        }
        try StateStore.update(fixture.paths) { state in
            for index in state.instances.indices {
                switch state.instances[index].name {
                case "Creative": state.instances[index].id = Self.creative
                case "My World": state.instances[index].id = Self.world
                case "生存 世界": state.instances[index].id = Self.chinese
                default: break
                }
            }
        }
        for instance in try StateStore.load(fixture.paths).instances where instance.name != "Survival" { fixture.ids[instance.name] = instance.id }
        return fixture
    }

    private func run(_ arguments: [String], _ fixture: Fixture, json: Bool = true) async -> (status: Int32, value: Value?, text: String) {
        let output = CommandCapture()
        // Global options go before any `--`, after which every word is an operand.
        let globals = ["--data-dir", fixture.root.path] + (json ? ["--json"] : [])
        let split = arguments.firstIndex(of: "--") ?? arguments.endIndex
        let status = await CLIApplication.run(Array(arguments[..<split]) + globals + Array(arguments[split...]), write: output.write)
        return (status, try? output.value, String(decoding: output.output + output.errors, as: UTF8.self))
    }

    private func shown(_ reference: String, _ fixture: Fixture) async -> String? {
        await run(["instance", "show", reference], fixture).value?["data"]["name"].string
    }

    @Test func fullIDsShortIDsAndExactNamesNameTheSameInstance() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        #expect(await shown(Self.creative.uuidString, fixture) == "Creative")
        #expect(await shown(Self.creative.uuidString.lowercased(), fixture) == "Creative")
        #expect(await shown("1a2b3c4d0", fixture) == "Creative")
        #expect(await shown("1A2B3C4D-0", fixture) == "Creative")
        #expect(await shown("id:1a2b3c4d1", fixture) == "My World")
        #expect(await shown("My World", fixture) == "My World")
        #expect(await shown("生存 世界", fixture) == "生存 世界")
        #expect(await shown("name:deadbeef", fixture) == "deadbeef")
        #expect(await shown("id:deadbeef", fixture) == "生存 世界")
        #expect(await run(["instance", "show", "id:\(Self.world.uuidString)"], fixture).value?["data"]["id"] == .string(Self.world.uuidString))

        // Names are exact and case-sensitive.
        let lowercase = await run(["instance", "show", "my world"], fixture)
        #expect(lowercase.status == 1 && lowercase.value?["error"]["code"] == .string("NOT_FOUND"))
        #expect(lowercase.value?["error"]["nextActions"] == .array([.object(["command": .array([.string("instance"), .string("list")])])]))
        let tooShort = await run(["instance", "show", "id:1a2b"], fixture)
        #expect(tooShort.status == 2 && tooShort.value?["error"]["code"] == .string("INVALID_ARGUMENT"))

        // Every interpretation that matches more than one instance is refused.
        for (reference, names) in [("Survival", ["Survival", "Survival"]), ("1a2b3c4d", ["Creative", "My World"]), ("deadbeef", ["deadbeef", "生存 世界"])] {
            let result = await run(["instance", "show", reference], fixture)
            #expect(result.status == 1 && result.value?["error"]["code"] == .string("AMBIGUOUS_TARGET"), "\(reference)")
            let candidates = try #require(try result.value?["error"]["details"].decode([Value].self))
            #expect(candidates.compactMap { $0["name"].string }.sorted() == names)
            for candidate in candidates {
                #expect(await run(["instance", "show", candidate["shortID"].string ?? ""], fixture).value?["data"]["id"] == candidate["id"])
            }
        }

        // The recovery command keeps the data directory it ran with.
        let text = await run(["instance", "show", "Nothing"], fixture, json: false)
        #expect(text.text.contains("No instance matches “Nothing”."))
        #expect(text.text.contains("Next: ruri instance list --data-dir " + CommandTextRenderer.shell([fixture.root.path])))
    }

    @Test func shortIDsAreUniqueAcrossTheWholeIndexAndNeverLookLikeNames() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let index = try TargetCatalog(paths: fixture.paths).index(.instance)
        #expect(index.shortID(Self.creative) == "1a2b3c4d0" && index.shortID(Self.world) == "1a2b3c4d1")
        // “deadbeef” is a name, so the instance whose ID starts with it needs more.
        #expect(index.shortID(Self.chinese) == "deadbeef2")
        var shortIDs: Set<String> = []
        for entry in index.entries {
            let short = index.shortID(entry.id)
            #expect(short.count >= 8 && !index.entries.contains { $0.name == short })
            #expect(try index.resolve(short) == entry.id.uuidString)
            #expect(try index.resolve(index.reference(entry)) == entry.id.uuidString)
            shortIDs.insert(short)
        }
        #expect(shortIDs.count == index.entries.count)
        #expect(index.reference(index.entries.first { $0.name == "deadbeef" }!) == "name:deadbeef")
        #expect(index.reference(index.entries.first { $0.name == "My World" }!) == "My World")
        #expect(index.entries.filter { $0.name == "Survival" }.allSatisfy { index.reference($0) == index.shortID($0.id) })
    }

    @Test func unresolvedTargetsNeverSelectOrWrite() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let original = try Data(contentsOf: fixture.paths.state)
        for arguments in [["instance", "rename", "Survival", "Renamed"], ["instance", "rename", "1a2b3c4d", "Renamed"], ["instance", "remove", "Nothing", "--yes"],
                          ["instance", "select", "survival"], ["config", "set", "memory.maximumMB", "4096", "--scope", "instance:Survival"]] {
            let result = await run(arguments, fixture)
            #expect(result.status == 1, "\(arguments)")
            #expect(["AMBIGUOUS_TARGET", "NOT_FOUND"].contains(result.value?["error"]["code"].string ?? ""), "\(arguments)")
        }
        #expect(try Data(contentsOf: fixture.paths.state) == original)
        #expect(await run(["instance", "rename", "1a2b3c4d0", "Renamed"], fixture).status == 0)
        let names = try StateStore.load(fixture.paths).instances.map(\.name)
        #expect(names.filter { $0 == "Renamed" }.count == 1 && !names.contains("Creative") && names.contains("My World"))
    }

    @Test func everyReferenceParameterResolvesBeforeTheCommandRuns() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        // Directories: “default” keeps its meaning, even beside a directory named default.
        let folder = fixture.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(await run(["directory", "add", folder.path, "--name", "default", "--layout", "managed"], fixture).status == 0)
        #expect(await run(["instance", "list", "--directory", "default"], fixture).value?["data"]["total"] == .integer(6))
        #expect(await run(["instance", "list", "--directory", "name:default"], fixture).value?["data"]["total"] == .integer(0))
        let custom = try #require(StateStore.load(fixture.paths).gameDirectories?.first?.id)
        let directories = try TargetCatalog(paths: fixture.paths).index(.directory)
        #expect(await run(["directory", "refresh", directories.shortID(custom)], fixture).status == 0)

        // Accounts by username or short ID.
        #expect(await run(["account", "add-offline", "Steve"], fixture).status == 0)
        let account = try #require(StateStore.load(fixture.paths).accounts.first?.id)
        #expect(await run(["account", "show", "Steve"], fixture).value?["data"]["account"]["id"] == .string(account.uuidString))
        let accounts = try TargetCatalog(paths: fixture.paths).index(.account)
        #expect(await run(["account", "show", accounts.shortID(account)], fixture).value?["data"]["account"]["username"] == .string("Steve"))

        // Scopes and instance options.
        #expect(await run(["config", "get", "--scope", "instance:My World"], fixture).status == 0)
        #expect(await run(["config", "set", "memory.maximumMB", "4096", "--scope", "instance:1a2b3c4d0"], fixture).status == 0)
        let creative = try #require(StateStore.load(fixture.paths).instances.first { $0.id == Self.creative })
        #expect(creative.launchOverrides?.memory?.maximumMB == 4096)
        #expect(await run(["session", "list", "--instance", "生存 世界"], fixture).status == 0)
        #expect(await run(["recovery", "list", "--instance", "My World"], fixture).status == 0)
        #expect(await run(["server", "list", "--instance", "1a2b3c4d1"], fixture).status == 0)
        // A full ID needs no current record, so history of removed instances stays reachable.
        #expect(await run(["session", "list", "--instance", UUID().uuidString], fixture).status == 0)

        // Sessions resolve within their instance.
        let session = try record(for: Self.world, fixture)
        let sessions = try TargetCatalog(paths: fixture.paths).index(.session, instance: Self.world)
        #expect(try TargetCatalog(paths: fixture.paths).resolve(sessions.shortID(session), as: .session, instance: Self.world) == session.uuidString)
        #expect(throws: OperationFailure.self) { try TargetCatalog(paths: fixture.paths).resolve(sessions.shortID(session), as: .session, instance: Self.creative) }
        let missing = await run(["session", "show", "My World", "abcdef12"], fixture)
        #expect(missing.value?["error"]["code"] == .string("NOT_FOUND"))
        #expect(missing.value?["error"]["nextActions"] == .array([.object(["command": .array(["session", "list", "--instance", Self.world.uuidString].map(Value.string))])]))
    }

    @Test func plainTextIsAStringOnlyWhereTheFieldTakesOne() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        func effective(_ key: String, _ scope: String = "app") async -> Value? {
            await run(["config", "get", key, "--scope", scope], fixture).value?["data"]["effective"]
        }
        #expect(await run(["config", "set", "appearance", "dark", "--scope", "app"], fixture).status == 0)
        #expect(await effective("appearance") == .string("dark"))
        #expect(await run(["config", "set", "appearance", "\"light\"", "--scope", "app"], fixture).status == 0)
        #expect(await effective("appearance") == .string("light"))
        #expect(await run(["config", "set", "jvmArguments", "--scope", "defaults", "--", "-XX:+UseG1GC -Dname=\"a b\""], fixture).status == 0)
        #expect(await effective("jvmArguments", "defaults") == .string("-XX:+UseG1GC -Dname=\"a b\""))
        #expect(await run(["config", "set", "java.path", "null", "--scope", "defaults"], fixture).status == 0)
        #expect(await effective("java.path", "defaults") == .null)
        let original = try Data(contentsOf: fixture.paths.state)
        for (key, value) in [("concurrentDownloads", "eight"), ("showSnapshots", "yes"), ("memory", "large")] {
            let result = await run(["config", "set", key, value, "--scope", key == "memory" ? "defaults" : "app"], fixture)
            #expect(result.status == 2 && result.value?["error"]["code"] == .string("INVALID_ARGUMENT"), "\(key)")
        }
        #expect(try Data(contentsOf: fixture.paths.state) == original)
    }

    @Test func completionOffersResolvableReferencesForEveryShell() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let words = ["ruri", "instance", "show", "--data-dir", fixture.root.path, ""]
        let zsh = CommandCompletion.candidates(path: ["instance", "show"], slot: .operand(0), words: words, index: 5, prefix: "", shell: .zsh)
        #expect(zsh.contains("My World:1.21.1") && zsh.contains("生存 世界:1.21.1") && zsh.contains("name\\:deadbeef:1.21.1"))
        #expect(zsh.filter { $0.hasSuffix(":Survival · 1.21.1") }.count == 2)
        let fish = CommandCompletion.candidates(path: ["instance", "show"], slot: .operand(0), words: words, index: 5, prefix: "", shell: .fish)
        #expect(fish.contains("My World\t1.21.1"))
        let bash = CommandCompletion.candidates(path: ["instance", "show"], slot: .operand(0), words: words, index: 5, prefix: "", shell: .bash)
        let index = try TargetCatalog(paths: fixture.paths).index(.instance)
        #expect(Set(try bash.map { try index.resolve($0) }).count == 6)

        // An ID prefix being typed completes to the matching short IDs.
        let typed = ["ruri", "instance", "show", "--data-dir=" + fixture.root.path, "1a2b3c4d"]
        let prefixed = CommandCompletion.candidates(path: ["instance", "show"], slot: .operand(0), words: typed, index: 4, prefix: "1a2b3c4d", shell: .bash)
        #expect(prefixed.contains("1a2b3c4d0") && prefixed.contains("1a2b3c4d1"))

        // Scopes, sessions, configuration keys, values and command paths.
        let scopes = CommandCompletion.candidates(path: ["config", "get"], slot: .option("scope"), words: ["ruri", "config", "get", "--data-dir", fixture.root.path, "--scope", ""], index: 6, prefix: "", shell: .zsh)
        #expect(scopes.starts(with: ["app", "defaults"]) && scopes.contains("instance\\:My World:1.21.1"))
        let session = try record(for: Self.world, fixture)
        let sessions = try TargetCatalog(paths: fixture.paths).index(.session, instance: Self.world)
        let sessionWords = ["ruri", "session", "show", "--data-dir", fixture.root.path, "'My World'", ""]
        #expect(CommandCompletion.candidates(path: ["session", "show"], slot: .operand(1), words: sessionWords, index: 6, prefix: "", shell: .bash) == [sessions.shortID(session)])
        let keys = CommandCompletion.candidates(path: ["config", "set"], slot: .operand(0), words: ["ruri", "config", "set", "--scope", "app", ""], index: 5, prefix: "", shell: .bash)
        #expect(keys.contains("appearance") && !keys.contains("memory.mode"))
        let values = CommandCompletion.candidates(path: ["config", "set"], slot: .operand(1), words: ["ruri", "config", "set", "java.path", ""], index: 4, prefix: "", shell: .bash)
        #expect(values == ["null"])
        let enumerated = CommandCompletion.candidates(path: ["config", "set"], slot: .operand(1), words: ["ruri", "config", "set", "appearance", ""], index: 4, prefix: "", shell: .bash)
        #expect(enumerated == ["system", "light", "dark"])
        let schema = CommandCompletion.candidates(path: ["schema"], slot: .operand(1), words: ["ruri", "schema", "instance", ""], index: 3, prefix: "", shell: .bash)
        #expect(schema.contains("list") && schema.contains("component"))
    }

    @Test func completionReadsNothingItCannotTrust() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing")
        #expect(CommandCompletion.candidates(path: ["instance", "show"], slot: .operand(0), words: ["ruri", "instance", "show", "--data-dir", missing.path, ""], index: 5, prefix: "", shell: .zsh).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: root.appendingPathComponent("state.json"))
        #expect(CommandCompletion.candidates(path: ["instance", "show"], slot: .operand(0), words: ["ruri", "instance", "show", "--data-dir", root.path, ""], index: 5, prefix: "", shell: .zsh).isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("state.json"), encoding: .utf8) == "broken")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["state.json"])

        // The shell protocol reaches the same candidates through ArgumentParser.
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let output = CommandCapture()
        let status = await CLIApplication.run(["---completion", "instance", "show", "--", "positional@0", "4", "0", "ruri", "instance", "show", "--data-dir=" + fixture.root.path, ""], write: output.write)
        #expect(status == 0)
        #expect(String(decoding: output.output, as: UTF8.self).split(separator: "\n").contains { $0.hasPrefix("My World") }, "\(String(decoding: output.output + output.errors, as: UTF8.self))")
    }

    @Test func generatedScriptsAreValidAndAskRuriForDynamicValues() async throws {
        let scripts = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scripts) }
        for (shell, checker) in [(CompletionShell.zsh, "/bin/zsh"), (.bash, "/bin/bash")] {
            let script = RuriCommand.completionScript(for: shell)
            #expect(script.contains("---completion"))
            let file = scripts.appendingPathComponent("ruri." + shell.rawValue)
            try Data(script.utf8).write(to: file)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: checker)
            process.arguments = ["-n", file.path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 0, "\(shell)")
        }
        let fish = RuriCommand.completionScript(for: .fish)
        #expect(fish.contains("---completion") && fish.contains("complete -c 'ruri'"))
        // File parameters use the shell's own path completion.
        #expect(RuriCommand.completionScript(for: .zsh).contains("_files"))
    }

    private func record(for instance: UUID, _ fixture: Fixture) throws -> UUID {
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        var record = GameSession(id: UUID(), instanceID: instance, instanceName: "My World", gameVersion: "1.21.1", loader: "vanilla", loaderVersion: nil,
                                 memoryMB: 1024, operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 123,
                                 createdAt: started, updatedAt: started.addingTimeInterval(60), state: .succeeded, stage: .finished, events: [], evidence: [])
        record.exit = .init(status: 0, reason: .exit, processID: 123, startedAt: started, endedAt: started.addingTimeInterval(60), stopRequested: false, durationSeconds: 60)
        try GameHistoryStore.record(record, paths: fixture.paths)
        return record.id
    }
}
