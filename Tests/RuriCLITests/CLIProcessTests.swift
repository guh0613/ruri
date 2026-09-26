import Foundation
import Testing
import RuriCore

private final class CLIProcessBundleMarker: NSObject {}

struct CLIProcessTests {
    private var executable: URL { Bundle(for: CLIProcessBundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("ruri-cli") }
    private func run(_ args: [String], paths: LauncherPaths) throws -> (Int32, OperationValue) {
        let process = Process(), output = Pipe()
        process.executableURL = executable
        process.arguments = args + ["--data-dir", paths.root.path, "--json", "--quiet"]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return (process.terminationStatus, try JSONDecoder().decode(OperationValue.self, from: data))
    }
    @Test(.timeLimit(.minutes(1))) func stdinPatchWaitsForAllFragments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri stdin \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["config", "apply", "--scope", "app", "--file", "-", "--data-dir", root.path, "--json"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data("{\"set\":".utf8))
        try await Task.sleep(for: .milliseconds(100))
        try input.fileHandleForWriting.write(contentsOf: Data("{\"concurrentDownloads\":7}}".utf8))
        try input.fileHandleForWriting.close()
        let result = try JSONDecoder().decode(OperationValue.self, from: output.fileHandleForReading.readDataToEndOfFile())
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(result["data"]["after"]["effective"]["concurrentDownloads"] == .integer(7))
    }
    @Test(.timeLimit(.minutes(1))) func detachedGameSurvivesCLIAndCanBeStoppedByAnotherInvocation() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri cli \(UUID())"))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let created = try run(["instance", "create", "--name", "Process Test", "--game", "1.21.1", "--directory", "default", "--no-install"], paths: paths)
        #expect(created.0 == 0)
        let id = try #require(created.1["data"]["instance"]["id"].string.flatMap(UUID.init(uuidString:)))
        #expect(try run(["account", "add-offline", "TestPlayer"], paths: paths).0 == 0)
        let accountID = try #require(StateStore.load(paths).activeAccountID)
        defer { try? FileManager.default.removeItem(at: LauncherPaths().root.appendingPathComponent(".account-locks/\(accountID).lock")) }
        let java = paths.root.appendingPathComponent("fake runtime/bin/java")
        try FileManager.default.createDirectory(at: java.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        if [ "$1" = "-XshowSettings:properties" ]; then
          printf 'java.version = 21.0.1\nos.arch = x86_64\njava.vendor = Fixture\n'
          exit 0
        fi
        trap 'exit 0' TERM
        printf 'fixture-game-output\n'
        while :; do sleep 0.05; done
        """
        try Data(script.utf8).write(to: java)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        let selection = String(decoding: try JSONEncoder().encode(OperationValue.object(["mode": .string("path"), "major": .null, "path": .string(java.path)])), as: UTF8.self)
        #expect(try run(["config", "set", "java", selection, "--scope", "instance:\(id)"], paths: paths).0 == 0)
        try StateStore.update(paths) { $0.instances[0].installed = true }
        try FileManager.default.createDirectory(at: paths.instance(id), withIntermediateDirectories: true)
        try Data(#"{"id":"1.21.1","mainClass":"Main","libraries":[],"minecraftArguments":"--username ${auth_player_name}","javaVersion":{"majorVersion":21}}"#.utf8).write(to: paths.manifest(id))
        let jar = paths.versions.appendingPathComponent("1.21.1/1.21.1.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: jar)
        let launched = try run(["launch", "start", id.uuidString], paths: paths)
        #expect(launched.0 == 0, "\(launched.1)")
        let sessionID = try #require(launched.1["data"]["id"].string.flatMap(UUID.init(uuidString:)))
        defer { if let record = try? GameSessionStore.load(paths: paths, instanceID: id, sessionID: sessionID) { try? GameMonitorClient.requestStop(paths: paths, record: record) } }
        var record = try GameSessionStore.load(paths: paths, instanceID: id, sessionID: sessionID)
        let deadline = Date().addingTimeInterval(10)
        while record.gameIdentity == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            record = try GameSessionStore.load(paths: paths, instanceID: id, sessionID: sessionID)
        }
        #expect(record.monitorIdentity?.isAlive == true)
        #expect(record.gameIdentity?.isAlive == true)
        #expect(try run(["session", "stop", id.uuidString, sessionID.uuidString, "--yes"], paths: paths).0 == 0)
        #expect(try run(["session", "wait", id.uuidString, sessionID.uuidString], paths: paths).0 == 0)
        #expect(try GameSessionStore.load(paths: paths, instanceID: id, sessionID: sessionID).state.isFinished)
    }
}
