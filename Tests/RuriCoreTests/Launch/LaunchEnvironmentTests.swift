import Foundation
import Testing
@testable import RuriCore

struct LaunchEnvironmentTests {
    private func paths() -> LauncherPaths { LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-env-\(UUID().uuidString)")) }

    @Test @MainActor func frozenEnvironmentReachesChildWithoutEvaluationOrSecretLogging() async throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Environment", gameVersion: "1.0"); instance.launchOverrides = .init()
        var state = PersistentState(); state.instances = [instance]
        state.settings.defaultEnvironment = "RURI_LITERAL=literal $HOME = value\r\nRURI_EMPTY=\r\nRURI_REMOVE\nRURI_TEST_TOKEN=example-token"
        try StateStore.save(state, to: paths)
        let snapshot = try instance.launchSnapshot(defaults: state.settings)
        try StateStore.update(paths) { $0.settings.defaultEnvironment = "RURI_LITERAL=changed" }
        let jar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("client".utf8).write(to: jar)
        let runtime = JavaRuntime(path: "/test/jdk/bin/java", version: "8", major: 8, architecture: "x86_64", vendor: "Test")
        let plan = try LaunchBuilder.build(instance: snapshot, manifest: VersionManifest(id: "1.0", mainClass: "Main", libraries: []), java: runtime, account: Account(username: "Player"), paths: paths)
        #expect(plan.environment["RURI_LITERAL"] == "literal $HOME = value")
        #expect(plan.environment["RURI_EMPTY"] == "" && plan.environment["JAVA_HOME"] == "/test/jdk")
        #expect(!plan.redactedCommand.contains("example-token"))
        let inherited = ["RURI_REMOVE": "old", "KEEP": "yes", "JAVA_TOOL_OPTIONS": "injected"]
        let edited = try LaunchEnvironment(snapshot.environmentVariables!).applying(to: inherited, java: plan.executable)
        #expect(edited["RURI_REMOVE"] == nil && edited["JAVA_TOOL_OPTIONS"] == nil && edited["KEEP"] == "yes")
        #expect(inherited["RURI_REMOVE"] == "old")
        let child = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf '%s\\n' \"$RURI_TEST_TOKEN\""], directory: paths.root, environment: plan.environment, customEnvironmentNames: plan.customEnvironmentNames)
        let process = GameProcess(); var output: [String] = []
        let exit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GameExit, any Error>) in
            do { try process.start(plan: child) { output.append($0) } onExit: { continuation.resume(returning: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        #expect(exit.succeeded && output == ["<redacted>"])
        for invalid in ["X=one\nX=two", "0INVALID=value", "JAVA_HOME=/override", "CLASSPATH=x", "X=\0"] {
            #expect(throws: (any Error).self) { try LaunchEnvironment(invalid) }
        }
        var local = instance.effectiveLaunchOverrides; local.environment = ""
        #expect(local.resolve(defaults: state.settings.defaultLaunchSettings).environment.isEmpty)
        local.setInheritance(true, for: .environment, defaults: state.settings.defaultLaunchSettings)
        #expect(!local.resolve(defaults: state.settings.defaultLaunchSettings).environment.isEmpty)
    }

    @Test func exactJavaMajorRespectsInheritancePackConstraintsAndArchitecture() throws {
        var defaults = AppSettings(); defaults.defaultJava = .major(21)
        var instance = GameInstance(name: "Java", gameVersion: "1.21.1"); instance.launchOverrides = .init()
        instance.supportedJavaMajors = [17, 21]
        let snapshot = try instance.launchSnapshot(defaults: defaults)
        #expect(snapshot.javaMajor == 21 && snapshot.javaPath == nil)
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(GameInstance.self, from: encoded).preferredJavaMajor(default: 17) == 21)
        func runtime(_ path: String, _ version: String, _ major: Int, _ architecture: String = "aarch64") -> JavaRuntime {
            .init(path: path, version: version, major: major, architecture: architecture, vendor: "Test")
        }
        let runtimes = [runtime("/21-old", "21.0.2", 21), runtime("/25", "25", 25), runtime("/21-new", "21.0.10", 21), runtime("/21-intel", "21.0.11", 21, "x86_64")]
        #expect(try JavaDiscovery.select(from: runtimes, major: snapshot.preferredJavaMajor(default: 17), architecture: "aarch64").path == "/21-new")
        #expect(throws: (any Error).self) { try snapshot.preferredJavaMajor(default: 25) }
        var unsupported = snapshot; unsupported.supportedJavaMajors = [17]
        #expect(throws: (any Error).self) { try unsupported.preferredJavaMajor(default: 17) }
        instance.launchOverrides?.java = .automatic
        let automatic = try instance.launchSnapshot(defaults: defaults)
        #expect(automatic.javaMajor == nil)
        #expect(try automatic.preferredJavaMajor(default: 17) == 17)
        instance.launchOverrides?.java = .path("/specific/java")
        #expect(try instance.launchSnapshot(defaults: defaults).javaMajor == nil)
        defaults.defaultJava = .major(0)
        #expect(throws: (any Error).self) { try defaults.defaultLaunchSettings.validate() }
    }

    @Test func portablePackKeepsJavaMajorAndExcludesLocalEnvironment() async throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Portable", gameVersion: "1.0"); instance.launchOverrides = .init()
        var state = PersistentState(); state.instances = [instance]
        state.settings.defaultJava = .major(21); state.settings.defaultEnvironment = "RURI_LOCAL_TOKEN=private-export-token"
        try StateStore.save(state, to: paths)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let service = InstanceTransfer(paths: paths), archive = paths.cache.appendingPathComponent("export.zip")
        try await service.export(instance, to: archive)
        let prepared = try await service.prepare(archive)
        #expect(prepared.instance.javaMajor == 21 && prepared.instance.javaPath == nil)
        #expect(prepared.instance.environmentVariables == nil)
        #expect(prepared.instance.resolvedLaunchSettings(defaults: state.settings).environment.isEmpty)
        await service.discard(prepared)
        let restored = try StateStore.load(paths)
        #expect(restored.settings.defaultJava == .major(21) && restored.settings.defaultEnvironment == state.settings.defaultEnvironment)
        #expect(restored.schemaVersion == StateStore.currentSchemaVersion)
    }
}
