import Testing
import Foundation
import ZIPFoundation
@testable import RuriCore

struct ArchiveAndLaunchTests {
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func makeZip(_ url: URL, entries: [(String, Data, Entry.EntryType)]) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data, type) in entries {
            try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<min(data.count, Int(position) + size))
            }
        }
    }
    @Test func zipRejectsTraversalAndSymlinks() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        for (index, entry) in [("../escape", Data("bad".utf8), Entry.EntryType.file), ("link", Data("../outside".utf8), Entry.EntryType.symlink)].enumerated() {
            let zip = root.appendingPathComponent("\(index).zip")
            try makeZip(zip, entries: [entry])
            #expect(throws: (any Error).self) { try SafeArchive.extract(zip, to: root.appendingPathComponent("out\(index)")) }
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
    }
    @Test func zipExtractsAndEnforcesSizeLimit() throws {
        let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("content.zip")
        let content = Data(repeating: 65, count: 10_000)
        try makeZip(zip, entries: [("mods/a.jar", content, .file)])
        let target = root.appendingPathComponent("out")
        try SafeArchive.extract(zip, to: target)
        #expect(try Data(contentsOf: target.appendingPathComponent("mods/a.jar")) == content)
        #expect(throws: (any Error).self) { try SafeArchive.extract(zip, to: root.appendingPathComponent("limited"), maxBytes: 100) }
    }
    @Test func launchPlanHandlesSpacesRedactionAndMissingFiles() throws {
        let root = try temporary().appendingPathComponent("space 中文")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let paths = LauncherPaths(root: root); try paths.prepare()
        let json = #"{"id":"1.0","mainClass":"net.minecraft.client.main.Main","libraries":[],"minecraftArguments":"--username ${auth_player_name} --gameDir ${game_directory} --accessToken ${auth_access_token}","javaVersion":{"majorVersion":8}}"#
        var manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(json.utf8))
        var instance = GameInstance(name: "Test", gameVersion: "1.0")
        instance.extraJVMArguments = #"-Dtest="hello world""#
        let java = JavaRuntime(path: "/test/bin/java", version: "8", major: 8, architecture: "x86_64", vendor: "Test")
        let account = try Account(username: "Player")
        #expect(throws: (any Error).self) { try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths) }
        let jar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: jar)
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, accessToken: "secret-token-value", paths: paths)
        #expect(plan.arguments.contains(paths.game(instance.id).path))
        #expect(plan.arguments.contains("-Dtest=hello world"))
        #expect(plan.arguments.filter { $0 == "-XstartOnFirstThread" }.count == 1)
        #expect(!plan.redactedCommand.contains("secret-token-value"))
        #expect(plan.redactedCommand.contains("<redacted>"))
        let legacy = try JSONDecoder().decode(Library.self, from: Data(#"{"name":"org.lwjgl.lwjgl:lwjgl:2.9.2"}"#.utf8))
        manifest.libraries = [legacy]
        let library = paths.libraries.appendingPathComponent(try Library.mavenPath(legacy.name))
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stub".utf8).write(to: library)
        let legacyPlan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths)
        #expect(!legacyPlan.arguments.contains("-XstartOnFirstThread"))
    }
}
