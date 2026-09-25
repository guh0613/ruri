import Foundation
import Testing
@testable import RuriCore

struct LaunchSettingsTests {
    @Test func oldPresentationSettingsKeepPreferencesWithoutEnablingDebugLogging() throws {
        let legacy = try JSONDecoder().decode(LaunchPresentation.self, from: Data(#"{"hideLauncher":true,"showLogs":true}"#.utf8))
        #expect(!legacy.debugLogging && legacy.hideLauncher && legacy.showLogs)
    }

    private func paths() -> LauncherPaths { .init(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-settings-\(UUID())")) }

    @Test func oldStatesKeepEveryExistingValueWhileNewInstancesInherit() throws {
        var old = GameInstance(name: "Old", gameVersion: "1.0"); old.memoryMB = 6144; old.width = 1440; old.extraJVMArguments = "-Dold=yes"
        let decoded = try JSONDecoder().decode(GameInstance.self, from: JSONEncoder().encode(old))
        var settings = AppSettings(); settings.defaultMemorySettings = .init(maximumMB: 8192); settings.defaultJava = .path("/new/java")
        settings.defaultJVMArguments = "-Dnew=yes"; settings.defaultGameArguments = "--demo"; settings.defaultWindow = .init(width: 1600, height: 900)
        let legacy = try decoded.launchSnapshot(defaults: settings)
        #expect(legacy.memoryMB == 6144 && legacy.width == 1440 && legacy.javaPath == nil)
        #expect(legacy.extraJVMArguments == "-Dold=yes" && legacy.extraGameArguments == nil)
        var modern = decoded; modern.launchOverrides = .init()
        let inherited = try modern.launchSnapshot(defaults: settings)
        #expect(inherited.memoryMB == 8192 && inherited.width == 1600 && inherited.javaPath == "/new/java")
        #expect(inherited.extraJVMArguments == "-Dnew=yes" && inherited.extraGameArguments == "--demo")
        #expect(modern.launchOverrides == .init() && inherited.launchOverrides == nil)
    }

    @Test func emptyArgumentsAndAutomaticJavaAreExplicitOverrides() throws {
        var settings = AppSettings(); settings.defaultJVMArguments = "-Dglobal=yes"; settings.defaultGameArguments = "--demo"; settings.defaultJava = .path("/global/java")
        var instance = GameInstance(name: "Local", gameVersion: "1.0")
        var overrides = InstanceLaunchOverrides(); overrides.java = .automatic; overrides.jvmArguments = ""; overrides.gameArguments = ""
        instance.launchOverrides = try JSONDecoder().decode(InstanceLaunchOverrides.self, from: JSONEncoder().encode(overrides))
        let resolved = try instance.launchSnapshot(defaults: settings)
        #expect(resolved.javaPath == nil && resolved.extraJVMArguments.isEmpty && resolved.extraGameArguments == nil)
        overrides.setInheritance(true, for: .java, defaults: settings.defaultLaunchSettings)
        #expect(overrides.resolve(defaults: settings.defaultLaunchSettings).java == .path("/global/java"))
        overrides.setInheritance(false, for: .java, defaults: settings.defaultLaunchSettings)
        settings.defaultJava = .automatic
        #expect(overrides.resolve(defaults: settings.defaultLaunchSettings).java == .path("/global/java"))
    }

    @MainActor @Test func argumentsSessionAndFrozenSnapshotUseTheSameEffectiveValues() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Inherited", gameVersion: "1.0"); instance.launchOverrides = .init()
        var state = PersistentState(); state.instances = [instance]; state.settings.defaultMemorySettings = .init(maximumMB: 6144)
        state.settings.defaultJVMArguments = #"-Dtest="two words""#; state.settings.defaultWindow = .init(width: 1600, height: 900)
        try StateStore.save(state, to: paths)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"1.0","mainClass":"Main","libraries":[],"minecraftArguments":"--username ${auth_player_name}","javaVersion":{"majorVersion":8}}"#.utf8))
        let jar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("fixture".utf8).write(to: jar)
        let java = JavaRuntime(path: "/test/java", version: "8", major: 8, architecture: "x86_64", vendor: "Test")
        let frozen = try instance.launchSnapshot(defaults: state.settings)
        let recorder = try GameSessionRecorder(paths: paths, instance: frozen, accountMode: "offline")
        #expect(recorder.record.memoryMB == 6144)
        try StateStore.update(paths) { $0.settings.defaultMemorySettings = .init(maximumMB: 8192); $0.settings.defaultWindow = .init(width: 1280, height: 720) }
        let plan = try LaunchBuilder.build(instance: frozen, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        #expect(plan.arguments.contains("-Xmx6144M") && plan.arguments.contains("-Dtest=two words"))
        #expect(plan.arguments.contains("1600") && plan.arguments.contains("900"))
        let next = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        #expect(next.arguments.contains("-Xmx8192M") && next.arguments.contains("720"))
        #expect(try StateStore.load(paths).instances[0].launchOverrides == .init())
        try recorder.fail(CancellationError(), cancelled: true)
    }

    @Test func concurrentOverrideEditsMergeButInheritanceAndValueConflict() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Concurrent", gameVersion: "1.0"); instance.launchOverrides = .init()
        var seed = PersistentState(); seed.instances = [instance]
        let baseline = try StateStore.save(seed, to: paths)
        var local = baseline; local.instances[0].launchOverrides?.memory = .init(maximumMB: 6144)
        try StateStore.update(paths) { $0.instances[0].launchOverrides?.jvmArguments = "-Dremote=true" }
        let merged = try StateStore.save(local, to: paths, basedOn: baseline)
        #expect(merged.instances[0].launchOverrides?.memory?.maximumMB == 6144 && merged.instances[0].launchOverrides?.jvmArguments == "-Dremote=true")
        var reset = merged; reset.instances[0].launchOverrides?.memory = nil
        try StateStore.update(paths) { $0.instances[0].launchOverrides?.memory = .init(maximumMB: 8192) }
        let bytes = try Data(contentsOf: paths.state)
        #expect(throws: (any Error).self) { try StateStore.save(reset, to: paths, basedOn: merged) }
        #expect(try Data(contentsOf: paths.state) == bytes)
    }

    @Test func portableExportFreezesEffectiveSettingsWithoutImportingGlobalPaths() async throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Export", gameVersion: "1.0"); instance.launchOverrides = .init()
        var state = PersistentState(); state.instances = [instance]; state.settings.defaultMemorySettings = .init(maximumMB: 8192)
        state.settings.defaultWindow = .init(width: 1600, height: 900, fullscreen: true); state.settings.defaultJava = .path("/machine/java")
        state.settings.defaultLaunchPresentation = .init(showLogs: true, debugLogging: true)
        state.settings.defaultJVMArguments = "-Dportable=yes"; try StateStore.save(state, to: paths)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        try Data("options".utf8).write(to: paths.game(instance.id).appendingPathComponent("options.txt"))
        let service = InstanceTransfer(paths: paths)
        for format in [InstanceExportFormat.ruri, .multimc] {
            let zip = paths.cache.appendingPathComponent("settings-" + format.rawValue + ".zip")
            try await service.export(instance, to: zip, format: format)
            let prepared = try await service.prepare(zip)
            #expect(prepared.instance.memoryMB == 8192 && prepared.instance.width == 1600 && prepared.instance.fullscreen == true)
            #expect(prepared.instance.extraJVMArguments == "-Dportable=yes" && prepared.instance.javaPath == nil)
            if format == .ruri { #expect(prepared.instance.launchPresentation == state.settings.defaultLaunchPresentation) }
            var destinationDefaults = AppSettings(); destinationDefaults.defaultMemorySettings = .init(maximumMB: 2048)
            #expect(try prepared.instance.launchSnapshot(defaults: destinationDefaults).memoryMB == 8192)
            await service.discard(prepared)
        }
    }

    @Test func invalidDefaultsFailOnlyWhenUsedAndDoNotRewriteOverrides() throws {
        var settings = AppSettings(); settings.defaultMemorySettings = .init(maximumMB: -1); settings.defaultJVMArguments = "\"unfinished"
        var legacy = GameInstance(name: "Fixed", gameVersion: "1.0")
        #expect(try legacy.launchSnapshot(defaults: settings).memoryMB == 4096)
        legacy.launchOverrides = .init()
        #expect(throws: (any Error).self) { try legacy.launchSnapshot(defaults: settings) }
        #expect(legacy.launchOverrides == .init())
        var values = LaunchSettingsValues(); values.java = .path("relative/java")
        #expect(throws: (any Error).self) { try values.validate() }
    }

    @Test func installationCompletionPreservesPreferencesEditedDuringDownloads() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var request = GameInstance(name: "Installing", gameVersion: "1.21.1", loader: .fabric); request.launchOverrides = .init()
        var seed = PersistentState(); seed.instances = [request]; try StateStore.save(seed, to: paths)
        var result = request; result.installed = true; result.loaderVersion = "0.19.5"; result.directoryID = GameDirectory.defaultID
        try StateStore.update(paths) { $0.instances[0].name = "Renamed"; $0.instances[0].launchOverrides?.memory = .init(maximumMB: 8192); $0.settings.defaultJVMArguments = "-Dnext=yes" }
        let saved = try StateStore.update(paths) { $0.instances[0] = try $0.instances[0].applyingInstallation(result, requested: request) }
        #expect(saved.instances[0].installed && saved.instances[0].loaderVersion == "0.19.5")
        #expect(saved.instances[0].name == "Renamed" && saved.instances[0].launchOverrides?.memory?.maximumMB == 8192)
        #expect(saved.settings.defaultJVMArguments == "-Dnext=yes")
        var changed = saved.instances[0]; changed.gameVersion = "1.20.1"
        #expect(throws: (any Error).self) { try changed.applyingInstallation(result, requested: request) }
    }
    @Test func fullscreenDefaultsAndExplicitWindowArgumentsReachTheLaunchPlan() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var source = GameInstance(name: "Window", gameVersion: "1.0"); source.launchOverrides = .init()
        var state = PersistentState(); state.instances = [source]
        state.settings.defaultWindow = .init(width: 1920, height: 1080, fullscreen: true)
        state.settings.defaultLaunchPresentation = .init(hideLauncher: true)
        try StateStore.save(state, to: paths)
        let jar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("client".utf8).write(to: jar)
        let manifest = VersionManifest(id: "1.0", mainClass: "Main", libraries: [])
        let java = JavaRuntime(path: "/test/java", version: "8", major: 8, architecture: "x86_64", vendor: "Test")
        let frozen = try source.launchSnapshot(defaults: state.settings)
        #expect(frozen.fullscreen == true && frozen.launchPresentation?.hideLauncher == true)
        let plan = try LaunchBuilder.build(instance: frozen, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        #expect(plan.arguments.contains("--fullscreen") && plan.arguments.contains("1920"))
        var custom = frozen; custom.extraGameArguments = "--width=900 --height 500 --fullscreen"
        let explicit = try LaunchBuilder.build(instance: custom, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        #expect(explicit.arguments.filter { $0 == "--fullscreen" }.count == 1)
        #expect(explicit.arguments.contains("--width=900") && !explicit.arguments.contains("--width"))
        #expect(explicit.arguments.contains("500") && !explicit.arguments.contains("1080"))
        let old = try JSONDecoder().decode(GameWindowSize.self, from: Data(#"{"width":1280,"height":720}"#.utf8))
        #expect(!old.fullscreen)
    }
}
