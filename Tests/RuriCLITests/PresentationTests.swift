import ArgumentParser
import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore
import RuriLocalization

@MainActor struct PresentationTests {
    private struct Fixture {
        let root: URL
        var paths: LauncherPaths { LauncherPaths(root: root) }
        let survival: UUID, world: UUID, account: UUID, directory: UUID, session: UUID
        /// A registered directory may not overlap the data directory.
        var folder: URL { root.appendingPathExtension("extra") }
        func remove() { for url in [root, folder] { try? FileManager.default.removeItem(at: url) } }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = LauncherPaths(root: root), service = InstanceService(paths: paths)
        let survival = try service.create(name: "Survival", game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        let world = try service.create(name: "My World", game: "1.20.4", selections: [], directoryID: GameDirectory.defaultID)
        let account = try AccountService(paths: paths).addOffline("Steve", activate: true)
        let folder = root.appendingPathExtension("extra")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let directory = try #require(try GameDirectoryStore.add(name: "Extra", url: folder, paths: paths).gameDirectories?.first?.id)
        let started = Date(timeIntervalSince1970: 1_790_000_000)
        var record = GameSession(id: UUID(), instanceID: survival.id, instanceName: "Survival", gameVersion: "1.21.1", loader: "vanilla", loaderVersion: nil,
                                 memoryMB: 1024, operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 123,
                                 createdAt: started, updatedAt: started.addingTimeInterval(90), state: .failed, stage: .finished, events: [], evidence: [])
        record.exit = .init(status: 1, reason: .exit, processID: 123, startedAt: started, endedAt: started.addingTimeInterval(90), stopRequested: false, durationSeconds: 90)
        try GameHistoryStore.record(record, paths: paths)
        return .init(root: root, survival: survival.id, world: world.id, account: account.id, directory: directory, session: record.id)
    }

    /// The text of one result, rendered as the CLI renders it after resolving targets.
    private func render(_ arguments: [String], _ value: Value = .null, error: OperationFailure? = nil, _ fixture: Fixture,
                        width: Int = 80, details: Bool = false, language: String = "en") throws -> String {
        let capture = CommandCapture(), stream = TerminalProfile.Stream(isTerminal: true, width: width)
        // The CLI parses and writes in the requested language.
        let (request, output) = try LocalizationContext.$current.withValue(.commandLine(language: language)) {
            let command = try #require(try RuriCommand.parseAsRoot(arguments + ["--data-dir", fixture.root.path]) as? any ExecutableCommand)
            return (try CommandTargets.resolve(command.request), CommandOutput(format: .text, details: details, write: capture.write, terminal: .init(output: stream, error: stream, environment: [:])))
        }
        output.setRequest(request)
        if let error { output.result(error: error) } else { output.result(value) }
        return String(decoding: error == nil ? capture.output : capture.errors, as: UTF8.self)
    }

    private func run(_ arguments: [String], _ fixture: Fixture) async -> String {
        let capture = CommandCapture()
        _ = await CLIApplication.run(arguments + ["--data-dir", fixture.root.path], write: capture.write, terminal: .pipe)
        return String(decoding: capture.output + capture.errors, as: UTF8.self)
    }

    @Test func everyCommandHasAPresentationForWhatItsResultIsFor() throws {
        for spec in CommandRegistry.commands {
            let presenter = try #require(CommandTextRenderer.presenter(spec.path), "\(spec.path)")
            // Anything that changes data reads outcome first; anything paged is a list.
            if spec.mutation { #expect(presenter.presentation == .change, "\(spec.path)") }
            if spec.options.contains(where: { $0.name == "limit" }) { #expect(presenter.presentation == .list, "\(spec.path)") }
        }
        #expect(CommandTextRenderer.presenter(["session", "logs"])?.presentation == .raw)
        #expect(CommandTextRenderer.presenter(["completions"])?.presentation == .raw)
        #expect(CommandTextRenderer.presenter(["session", "diagnose"])?.presentation == .diagnosis)
        #expect(CommandTextRenderer.presenter(["doctor"])?.presentation == .diagnosis)
    }

    /// One representative result of each family, with what must be visible in it.
    private func samples(_ fixture: Fixture) -> [(arguments: [String], value: Value, needles: [String])] {
        let survival = fixture.survival.uuidString, session = fixture.session.uuidString, world = fixture.world.uuidString
        func page(_ items: [Value], total: Int? = nil, more: Bool = false) -> Value {
            var page: [String: Value] = ["items": .array(items), "offset": .integer(0), "hasMore": .bool(more)]
            if let total { page["total"] = .integer(total) }
            return .object(page)
        }
        let runtime: Value = .object(["path": .string("/Library/Java/JavaVirtualMachines/zulu-21.jdk/Contents/Home/bin/java"), "major": .integer(21), "version": .string("21.0.4"),
                                      "architecture": .string("aarch64"), "vendor": .string("Azul")])
        let version: Value = .object(["id": .string("tBX3XmVb"), "name": .string("Sodium 0.6.0"), "number": .string("mc1.21.1-0.6.0"), "channel": .string("release"),
                                      "publishedAt": .string("2026-09-01T10:00:00Z"), "gameVersions": .array(["1.21", "1.21.1", "1.21.2", "1.21.3"].map(Value.string)),
                                      "loaders": .array([.string("fabric"), .string("neoforge")]), "filename": .string("sodium-0.6.0.jar"), "bytes": .integer(1_200_000)])
        let manual: Value = .array([.object(["fileID": .integer(5123456), "filename": .string("Mod With Spaces.jar"), "pageURL": .string("https://www.curseforge.com/minecraft/mc-mods/example/files/5123456"),
                                             "bytes": .integer(4096), "sha1": .null, "md5": .null])])
        let backup: Value = .object(["id": .string("2026-10-20T16-28-03Z-F8AC160B-C28E-497C-91CC-1A0B3E9FF2BF.zip"), "world": .string("New World"), "worldName": .string("New World"),
                                     "createdAt": .string("2026-10-20T16:28:03Z"), "bytes": .integer(52_000_000)])
        return [
            (["directory", "list"], page([.object(["id": .string(GameDirectory.defaultID.uuidString), "name": .string("default"), "path": .string(fixture.root.path), "layout": .string("managed"), "detached": .bool(false)]),
                                          .object(["id": .string(fixture.directory.uuidString), "name": .string("Extra"), "path": .string("/Volumes/Games/Extra folder"), "layout": .string("minecraft"), "detached": .bool(false), "available": .bool(false)])], total: 2),
             ["Extra", "Unavailable"]),
            (["java", "list"], page([.object(["path": runtime["path"], "managedID": .null, "source": .string("discovery"), "runtime": runtime, "issue": .null]),
                                     .object(["path": .string("/opt/broken java/bin/java"), "managedID": .null, "source": .string("manual"), "runtime": .null, "issue": .string("Java could not be started.")])], total: 2),
             ["21.0.4", "Needs attention:", "Java could not be started."]),
            (["java", "remove", "zulu-21", "--yes"], .object(["id": .string("zulu-21"), "trashedPath": .string("/Users/me/.Trash/zulu-21"), "dryRun": .bool(false)]), ["Completed:", "/Users/me/.Trash/zulu-21"]),
            (["account", "list"], page([.object(["id": .string(fixture.account.uuidString), "kind": .string("offline"), "username": .string("Steve"), "uuid": .string("5627dd98e6be3c21b8a8e92344183641"), "server": .null])], total: 1),
             ["Steve", "Offline Account"]),
            (["account", "login", "start", "--provider", "microsoft"], .object(["flowID": .string("6F0C8A1E-0000-4000-8000-000000000001"), "verificationURL": .string("https://microsoft.com/link"),
                                                                              "userCode": .string("ABCD-EFGH"), "expiresAt": .string("2026-10-21T10:15:00Z"), "dryRun": .bool(false)]),
             ["https://microsoft.com/link", "ABCD-EFGH", "ruri account login complete 6F0C8A1E-0000-4000-8000-000000000001"]),
            (["session", "list"], page([.object(["id": .string(session), "instanceID": .string(survival), "instanceName": .string("Survival"), "state": .string("failed"), "stage": .string("finished"),
                                                 "createdAt": .string("2026-09-21T13:46:40Z"), "finished": .bool(true), "playedSeconds": .number(90), "gameExitCode": .integer(1), "segments": .array([]),
                                                 "trackingVersion": .null, "failure": .string("The game exited with code 1."), "activity": .string("finished")])], more: true),
             ["Survival", "Failed", "The game exited with code 1.", "Next page:"]),
            (["session", "diagnose", survival, session], .object(["sessionID": .string(session), "summary": .string("The game crashed while loading mods."), "facts": .array([.string("Java 21")]),
                "findings": .array([.object(["id": .string("mixin"), "title": .string("A mod failed to apply its changes"), "explanation": .string("Sodium could not patch the renderer."), "confidence": .string("reported"),
                    "steps": .array([.string("Update Sodium.")]), "actions": .array([.string("mods")]), "evidence": .array([.object(["documentID": .string("latest.log"), "line": .integer(42), "excerpt": .string("Mixin apply failed")])])])]),
                "limitations": .array([.string("The crash report was not found.")])]),
             ["The game crashed while loading mods.", "1. A mod failed to apply its changes", "latest.log:42", "Next: ruri content list \(survival)"]),
            (["catalog", "search", "sodium"], .object(["items": .array([.object(["id": .string("AANobbMI"), "provider": .string("modrinth"), "title": .string("Sodium"), "type": .string("mod"), "pageURL": .string("https://modrinth.com/mod/sodium")])]),
                                                       "total": .integer(120), "offset": .integer(0), "hasMore": .bool(true)]),
             ["Sodium", "AANobbMI", "Showing 1–1 of 120.", "Next page: ruri catalog search sodium --offset 1"]),
            (["catalog", "versions", "AANobbMI"], page([version], total: 1), ["mc1.21.1-0.6.0", "tBX3XmVb"]),
            (["content", "list", survival], page([.object(["filename": .string("sodium-0.6.0.jar"), "title": .string("Sodium"), "version": .string("0.6.0"), "kind": .string("mod"), "enabled": .bool(false), "bytes": .integer(1_200_000), "managed": .null])], total: 1),
             ["Sodium", "Disabled", "sodium-0.6.0.jar"]),
            (["content", "install", survival, "AANobbMI"], .object(["dryRun": .bool(true), "project": .object(["id": .string("AANobbMI"), "provider": .string("modrinth"), "title": .string("Sodium"), "type": .string("mod"), "pageURL": .null]),
                "version": version, "downloadBytes": .integer(1_200_000), "files": .array([.object(["record": .object(["title": .string("Sodium"), "version": .string("0.6.0"), "filename": .string("sodium-0.6.0.jar")]), "action": .string("install")])]),
                "manualFiles": manual]),
             ["Preview (not executed):", "Sodium (AANobbMI)", "--manual", "5123456", "https://www.curseforge.com/minecraft/mc-mods/example/files/5123456"]),
            (["pack", "update", survival, "--version", "2.0", "--dry-run"], .object(["dryRun": .bool(true), "format": .string("mrpack"), "name": .string("Fabulously Optimized"), "packVersion": .string("2.0"),
                "gameVersion": .string("1.21.1"), "files": .integer(120), "bytes": .integer(300_000_000), "manualFiles": .array([]), "curseForgeFiles": .integer(0), "warnings": .array([]),
                "changes": .array([.object(["path": .string("config/sodium-options.json"), "action": .string("keep"), "conflict": .bool(true), "explanation": .string("Changed locally since the last update.")]),
                                   .object(["path": .string("mods/sodium.jar"), "action": .string("replace"), "conflict": .bool(false), "explanation": .null])])]),
             ["Preview (not executed):", "Fabulously Optimized 2.0", "Conflicts with local changes:", "config/sodium-options.json"]),
            (["world", "list", survival], page([.object(["folder": .string("New World"), "name": .string("New World"), "version": .string("1.21.1"), "gameType": .integer(0), "hardcore": .bool(true),
                                                         "bytes": .integer(52_000_000), "lastPlayed": .string("2026-10-19T20:00:00Z"), "error": .null]),
                                                .object(["folder": .string("Broken"), "name": .string("Broken"), "version": .null, "gameType": .null, "hardcore": .bool(false), "bytes": .null, "lastPlayed": .null, "error": .string("level.dat is damaged.")])], total: 2),
             ["New World", "level.dat is damaged."]),
            (["world", "backup", "list", survival], page([backup], total: 1), ["2026-10-20T16-28-03Z-F8AC160B-C28E-497C-91CC-1A0B3E9FF2BF.zip"]),
            (["world", "backup", "restore", survival, backup["id"].string!, "--yes", "--dry-run"], .object(["dryRun": .bool(true), "backup": backup, "replace": .bool(false)]), ["Preview (not executed):", "New World"]),
            (["datapack", "order", "get", survival, "New World"], .object(["keys": .array([.string("file/Example.zip"), .string("vanilla")]), "dryRun": .bool(false)]), ["1  file/Example.zip", "2  vanilla"]),
            (["schematic", "info", survival, "house.litematic"], .object(["entry": .object(["path": .string("house.litematic"), "directory": .bool(false), "bytes": .integer(2048), "modifiedAt": .string("2026-10-01T08:00:00Z")]),
                "name": .string("House"), "author": .string("Alex"), "description": .null, "dimensions": .array([.integer(12), .integer(8), .integer(10)]), "blocks": .integer(640), "regions": .integer(1),
                "formatVersion": .integer(6), "gameDataVersion": .integer(3953)]),
             ["House", "12 × 8 × 10", "640"]),
            (["server", "list", "--instance", survival], page([.object(["id": .integer(0), "name": .string("Hypixel"), "address": .string("mc.hypixel.net"), "resourcePacks": .string("ask"), "validAddress": .bool(true)])], total: 1),
             ["Hypixel", "mc.hypixel.net"]),
            (["server", "query", "mc.hypixel.net"], .object(["address": .string("mc.hypixel.net"), "description": .string("§aHypixel Network\n§eSkyBlock"), "version": .string("Requires MC 1.8 / 1.21"), "protocolVersion": .integer(47),
                                                            "online": .integer(31000), "maximum": .integer(200000), "latencyMilliseconds": .integer(42), "playerSample": .array([]), "queriedAt": .string("2026-10-21T10:00:00Z")]),
             ["mc.hypixel.net", "Hypixel Network", "SkyBlock"]),
            (["recovery", "list"], .object(["items": .array([.object(["kind": .string("instance-move"), "target": .string(survival), "transaction": .string("8D1C0000-0000-4000-8000-000000000009"), "committed": .bool(false),
                                                                      "workspace": .string(fixture.root.path + "/moves/8D1C"), "nextAction": .array(["recovery", "apply", "instance-move", survival, "--transaction", "8D1C0000-0000-4000-8000-000000000009"].map(Value.string))])]),
                                             "total": .integer(1), "offset": .integer(0), "hasMore": .bool(false), "issues": .array([.object(["instanceID": .string(world), "error": .string("Permission denied.")])])]),
             ["instance-move · Survival (", "Next: ruri recovery apply instance-move \(survival) --transaction 8D1C0000-0000-4000-8000-000000000009", "Could not check:", "Permission denied."]),
            (["doctor"], .object(["healthy": .bool(true), "checks": .array([.object(["check": .string("state"), "ok": .bool(true), "details": .null]),
                                                                            .object(["check": .string("instance"), "ok": .bool(true), "details": .object(["id": .string(survival), "java": runtime])])])]),
             ["✓", "Survival ("]),
            (["app", "info"], .object(["version": .string("1.4.0"), "schemaVersion": .integer(1), "application": .string("/Applications/Ruri.app"), "cli": .string("/Applications/Ruri.app/Contents/Helpers/ruri-cli"),
                                       "dataDirectory": .string(fixture.root.path)]), ["1.4.0", "/Applications/Ruri.app"]),
            (["cli", "status"], .object(["executable": .string("/Applications/Ruri.app/Contents/Helpers/ruri-cli"), "link": .string("/usr/local/bin/ruri"), "target": .null, "installed": .bool(false), "owned": .bool(false),
                                         "legacyLink": .null, "packageManager": .null, "requiresAuthorization": .bool(false), "onPath": .bool(true)]), ["ruri cli install"]),
            (["cache", "clean", "--dry-run"], .object(["bytes": .integer(12_000_000), "files": .integer(34), "dryRun": .bool(true)]), ["Preview (not executed):", "34 files"]),
            (["instance", "move", survival, "--directory", "Extra"], .object(["dryRun": .bool(false), "instanceID": .string(survival), "source": .string(fixture.root.path + "/instances/" + survival),
                "destination": .string("/Volumes/Games/Extra folder/instances/" + survival), "files": .integer(10), "bytes": .integer(1_447), "retainedGameDirectory": .null,
                "warning": .string("The old folder could not be removed."), "preservedFiles": .array([.string("/Volumes/Games/kept files")])]),
             ["Completed:", "Survival (", "Extra (", "Warning: The old folder could not be removed.", "/Volumes/Games/kept files"]),
            (["directory", "run", "set", survival, "shared", "--dry-run"], .object(["dryRun": .bool(true), "source": .string("/games/a"), "target": .string("/games/shared"), "sourceFiles": .integer(6), "targetFiles": .integer(3),
                "sourceBytes": .integer(1_447), "targetBytes": .integer(100), "canCopy": .bool(false), "copyIssue": .string("The shared folder is not empty."), "otherInstances": .array([.string("My World")])]),
             ["Preview (not executed):", "The shared folder is not empty.", "My World"]),
        ]
    }

    @Test func everyFamilyReadsByPurposeAtEveryWidthAndInBothLanguages() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        // A field dump shows machine keys such as instanceID: or dryRun:.
        let dump = try Regex("^\\s*[a-z]+[A-Z][A-Za-z]*(\\.[A-Za-z]+)*: ")
        for sample in samples(fixture) {
            let command = try #require(try RuriCommand.parseAsRoot(sample.arguments) as? any ExecutableCommand)
            let presentation = try #require(CommandTextRenderer.presenter(command.request.spec.path)).presentation
            let english = try render(sample.arguments, sample.value, fixture)
            for needle in sample.needles { #expect(english.contains(needle), "\(sample.arguments): \(needle)\n\(english)") }
            if presentation == .change, sample.arguments.contains("--dry-run") || sample.value["dryRun"] == .bool(false) {
                #expect(english.hasPrefix("Preview (not executed): ") || english.hasPrefix("Completed: ") || sample.arguments.contains("login"), "\(sample.arguments)\n\(english)")
            }
            for width in [40, 80, 120] {
                for language in ["en", "zh-Hans"] {
                    let text = try render(sample.arguments, sample.value, fixture, width: width, language: language)
                    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    #expect(!lines.contains { $0.contains(dump) }, "\(sample.arguments) \(width) \(language)\n\(text)")
                    #expect(!lines.contains { $0.hasSuffix(" null") || $0.hasSuffix(": null") }, "\(sample.arguments)\n\(text)")
                    #expect(!text.contains("…"), "\(sample.arguments) \(width)")
                    for line in lines where TerminalText.width(line) > width {
                        // Only words that must stay whole, such as paths, URLs and commands, may overflow.
                        let words = line.trimmingCharacters(in: .whitespaces)
                        #expect(!words.contains(" ") || line.contains("/") || line.contains("ruri ") || line.contains("--manual"), "\(sample.arguments) \(width) \(language): \(line)")
                    }
                    if language == "zh-Hans" { #expect(text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, "\(sample.arguments)\n\(text)") }
                }
            }
        }
    }

    @Test func targetsAreNamedAsTheyWereBeforeTheCommandRan() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let index = try TargetCatalog(paths: fixture.paths).index(.instance)
        let survival = index.shortID(fixture.survival), world = index.shortID(fixture.world)
        let renamed = await run(["instance", "rename", "Survival", "Hardcore"], fixture)
        #expect(renamed.hasPrefix("Completed: Rename an instance."))
        #expect(renamed.contains("Instance  Survival (\(survival))") && renamed.contains("Name      Hardcore"), "\(renamed)")
        let removed = await run(["instance", "remove", "My World", "--yes"], fixture)
        #expect(try StateStore.load(fixture.paths).instances.count == 1)
        #expect(removed.contains("My World (\(world))"), "\(removed)")
        let preview = await run(["instance", "remove", "Hardcore", "--dry-run"], fixture)
        #expect(preview.hasPrefix("Preview (not executed): Move instance-owned files to the Trash"))
        #expect(try StateStore.load(fixture.paths).instances.count == 1)
    }

    @Test func sessionsListShortIDsWithinTheirInstance() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let list = await run(["session", "list"], fixture)
        let short = try TargetCatalog(paths: fixture.paths).index(.session, instance: fixture.survival).shortID(fixture.session)
        #expect(list.contains(short) && !list.contains(fixture.session.uuidString), "\(list)")
        #expect(try TargetCatalog(paths: fixture.paths).resolve(short, as: .session, instance: fixture.survival) == fixture.session.uuidString)
        #expect(list.contains("Failed") && list.contains("1m 30s"), "\(list)")
        #expect(await run(["session", "list", "--details"], fixture).contains(fixture.session.uuidString))
    }

    @Test func diagnosisLeadsWithTheConclusionAndLimitsEvidenceUnlessDetailed() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let evidence = (1...5).map { Value.object(["documentID": .string("latest.log"), "line": .integer($0), "excerpt": .string("line \($0)")]) }
        let value: Value = .object(["sessionID": .string(fixture.session.uuidString), "summary": .string("Out of memory."), "facts": .array([]), "limitations": .array([]),
            "findings": .array([.object(["id": .string("memory"), "title": .string("Not enough memory"), "explanation": .string("The game ran out of memory."), "confidence": .string("possible"),
                                         "steps": .array([.string("Raise the memory limit.")]), "actions": .array([.string("settings"), .string("collect")]), "evidence": .array(evidence)])])])
        let arguments = ["session", "diagnose", fixture.survival.uuidString, fixture.session.uuidString]
        let compact = try render(arguments, value, fixture), detailed = try render(arguments, value, fixture, details: true)
        #expect(compact.hasPrefix("Out of memory.\n\n1. Not enough memory · Possible Causes to Check"))
        #expect(compact.contains("latest.log:3") && !compact.contains("latest.log:4") && compact.contains("2 more lines; use --details to see them."))
        #expect(detailed.contains("latest.log:5"))
        #expect(compact.contains("Next: ruri config get --scope instance:\(fixture.survival.uuidString)"))
        #expect(compact.contains("Next: ruri session export \(fixture.survival.uuidString) \(fixture.session.uuidString) ruri-session-"))
    }

    @Test func errorsShowThePathInTheWayManualDownloadsAndFailedChecksFirst() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let conflict = try render(["cli", "install"], error: .init("PATH_CONFLICT", "Another program owns this link.", details: .object(["path": .string("/usr/local/bin/ruri")])), fixture)
        #expect(conflict.contains("  Path  /usr/local/bin/ruri") && !conflict.contains("Preserved files"), "\(conflict)")
        let manual = try render(["content", "install", fixture.survival.uuidString, "example"], error: .init("MANUAL_DOWNLOAD_REQUIRED", "Download files by hand.", details: .object(["files": .array([
            .object(["fileID": .integer(77), "filename": .string("Example.jar"), "pageURL": .string("https://www.curseforge.com/example/77"), "bytes": .integer(1), "sha1": .null, "md5": .null])])])), fixture)
        #expect(manual.contains("--manual") && manual.contains("77  Example.jar") && manual.contains("https://www.curseforge.com/example/77"), "\(manual)")
        let report: Value = .object(["healthy": .bool(false), "checks": .array([
            .object(["check": .string("state"), "ok": .bool(true), "details": .null]),
            .object(["check": .string("credentials"), "ok": .bool(false), "details": .object(["accountID": .string(fixture.account.uuidString), "availability": .string("missing")])])])])
        let doctor = try render(["doctor"], error: .init("CHECKS_FAILED", "One or more checks failed.", details: report), fixture)
        let lines = doctor.split(separator: "\n").map(String.init)
        #expect(lines.count == 4 && lines[1].hasPrefix("  ✗ Credentials of Steve (") && lines[2] == "    Not found in the keychain" && lines[3] == "  ✓ Saved data", "\(doctor)")
    }

    @Test func emptyResultsSayWhatToDoNext() async throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        #expect(await run(["recovery", "list"], fixture) == "Nothing needs recovery.\n")
        #expect(try render(["java", "list"], .object(["items": .array([]), "total": .integer(0), "offset": .integer(0), "hasMore": .bool(false)]), fixture)
            .hasPrefix("There is nothing here yet.\nNext: ruri java available"))
        #expect(try render(["content", "update-check", fixture.survival.uuidString], .object(["changed": .bool(false), "updates": .array([])]), fixture) == "Everything is up to date.\n")
        #expect(try render(["cache", "status"], .object(["bytes": .integer(0), "files": .integer(0)]), fixture) == "The download cache has nothing to clean.\n")
    }
}
