import Foundation
import Testing
@testable import RuriCore

struct JVMTuningTests {
    /// What `-XX:+PrintFlagsFinal` lists on each runtime, reduced to the flags the rules read.
    private static func runtime(_ major: Int) -> JavaCapabilities {
        var flags: [String: JavaCapabilities.Kind] = ["OmitStackTraceInFastThrow": .product, "UseG1GC": .product, "G1NewSizePercent": .experimental,
                                                     "G1ReservePercent": .product, "MaxGCPauseMillis": .product, "G1HeapRegionSize": .product]
        if major >= 15 { flags["UseZGC"] = .product }
        if (21...23).contains(major) { flags["ZGenerational"] = .product }
        if major == 24 { flags["UseCompactObjectHeaders"] = .experimental }
        if major >= 25 { flags["UseCompactObjectHeaders"] = .product }
        return .init(flags: flags, unsafeMemoryAccessOption: major >= 23)
    }
    private let roomy = MemoryAvailability(physicalMB: 32768, availableMB: 24576)
    private let pack = MemoryWorkload(gameVersion: "1.20.1", loader: .fabric, modCount: 120, modBytes: 1536 * 1_048_576)
    private let vanilla = MemoryWorkload(gameVersion: "1.20.1", loader: .vanilla)

    private func tune(_ major: Int, memory: LaunchMemory, workload: MemoryWorkload, availability: MemoryAvailability? = nil, mode: JVMTuningMode = .recommended,
                      capabilities: JavaCapabilities?? = nil, arguments: [String] = []) -> JVMTuning {
        JVMTuning.resolve(.init(mode: mode, javaMajor: major, capabilities: capabilities ?? Self.runtime(major), memory: memory, workload: workload,
                                availability: availability ?? roomy, arguments: arguments))
    }
    private func automatic(_ workload: MemoryWorkload, on availability: MemoryAvailability? = nil) throws -> LaunchMemory {
        try MemorySettings(mode: .automatic).resolve(availability: availability ?? roomy, workload: workload)
    }
    private func manual(_ megabytes: Int) throws -> LaunchMemory { try MemorySettings(maximumMB: megabytes).resolve() }

    @Test func parsesFlagListingsOfOldAndCurrentRuntimes() {
        let listing = """
        [Global flags]
            uintx G1NewSizePercent                          = 5                                   {experimental}
             bool UseG1GC                                   = true                                      {product} {ergonomic}
            ccstr AbortVMOnException                        =                                        {diagnostic} {default}
             bool UseCompactObjectHeaders                   = false                          {product lp64_product} {default}
             intx MaxNodeLimit                              = 80000                                {C2 product}
        openjdk version "21.0.10" 2026-01-20 LTS
        """
        let flags = JavaCapabilities.parse(listing)
        #expect(flags == ["G1NewSizePercent": .experimental, "UseG1GC": .product, "AbortVMOnException": .diagnostic,
                          "UseCompactObjectHeaders": .product, "MaxNodeLimit": .product])
    }

    @Test func smallAndVanillaHeapsGetTheOfficialLauncherG1Settings() throws {
        let tuning = tune(17, memory: try manual(4096), workload: vanilla)
        #expect(tuning.collector == .g1)
        #expect(tuning.values == ["-XX:+UnlockExperimentalVMOptions", "-XX:-OmitStackTraceInFastThrow", "-Djava.net.useSystemProxies=true",
                                  "-XX:+UseG1GC", "-XX:G1NewSizePercent=20", "-XX:G1ReservePercent=20", "-XX:MaxGCPauseMillis=50", "-XX:G1HeapRegionSize=8M"])
        #expect(tune(21, memory: try manual(8192), workload: vanilla).values.contains("-XX:G1HeapRegionSize=16M"))
        #expect(tune(21, memory: try manual(12288), workload: vanilla).values.contains("-XX:G1HeapRegionSize=32M"))
        // Java 17's ZGC is single-generation: a large pack stays on G1 there.
        #expect(tune(17, memory: try automatic(pack), workload: pack).collector == .g1)
    }

    @Test func largePacksOnNewJavaUseGenerationalZGCWithARaisedAutomaticHeap() throws {
        let memory = try automatic(pack)
        #expect(memory.maximumMB >= JVMTuning.zgcMinimumHeapMB)
        let java21 = tune(21, memory: memory, workload: pack)
        #expect(java21.collector == .z && java21.values.contains("-XX:+UseZGC") && java21.values.contains("-XX:+ZGenerational"))
        #expect(!java21.values.contains { $0.contains("G1") || $0 == "-XX:+UnlockExperimentalVMOptions" })
        let raised = try #require(java21.heapRaisedToMB)
        #expect(java21.heapRaisedFromMB == memory.maximumMB && raised > memory.maximumMB && raised <= memory.estimate!.ceilingMB && raised % 256 == 0)
        #expect(java21.applying(to: memory).maximumMB == raised && java21.applying(to: memory).initialBytes == memory.initialBytes)
        // 23 generational by default, 24 and later removed the switch.
        let java25 = tune(25, memory: memory, workload: pack)
        #expect(java25.collector == .z && !java25.values.contains("-XX:+ZGenerational"))
        // A heap the user chose is kept as chosen.
        let chosen = tune(21, memory: try manual(8192), workload: pack)
        #expect(chosen.collector == .z && chosen.heapRaisedToMB == nil)
    }

    @Test func zgcNeedsContentAndMemoryToSpare() throws {
        #expect(tune(21, memory: try manual(8192), workload: vanilla).collector == .g1, "few mods: G1 pauses stay short")
        let smallMachine = MemoryAvailability(physicalMB: 8192, availableMB: 6144)
        #expect(tune(21, memory: try manual(6144), workload: pack, availability: smallMachine).collector == .g1)
        let busy = MemoryAvailability(physicalMB: 16384, availableMB: 7000)
        let memory = try automatic(pack, on: busy)
        #expect(memory.maximumMB >= JVMTuning.zgcMinimumHeapMB)
        let tuning = tune(21, memory: memory, workload: pack, availability: busy)
        #expect(tuning.collector == .g1 && tuning.notes == [.zgcHeadroom] && tuning.heapRaisedToMB == nil)
    }

    @Test func userArgumentsWin() throws {
        let chosen = tune(21, memory: try manual(8192), workload: pack, arguments: ["-XX:+UseShenandoahGC"])
        #expect(chosen.collector == nil && chosen.notes == [.collectorChosenByUser] && !chosen.values.contains { $0.contains("GC") })
        let off = tune(21, memory: try manual(4096), workload: vanilla, arguments: ["-XX:-UseG1GC", "-XX:+UseParallelGC"])
        #expect(off.collector == nil)
        let pause = tune(21, memory: try manual(4096), workload: vanilla,
                         arguments: ["-XX:MaxGCPauseMillis=100", "-XX:+OmitStackTraceInFastThrow", "-Dhttps.proxyHost=127.0.0.1", "-XX:+UnlockExperimentalVMOptions"])
        #expect(pause.collector == .g1 && pause.values.contains("-XX:G1NewSizePercent=20"))
        #expect(!pause.values.contains { $0.hasPrefix("-XX:MaxGCPauseMillis") || $0.contains("OmitStackTrace") || $0.contains("Proxies") || $0.contains("Unlock") })
        #expect(!JVMTuning.isCollectorChoice("-XX:+UseGCOverheadLimit") && !JVMTuning.isCollectorChoice("-XX:MaxGCPauseMillis=50"))
    }

    @Test func unknownRuntimesOnlyGetOptionsNoJVMCanRefuse() throws {
        let unknown = tune(21, memory: try manual(8192), workload: pack, capabilities: .some(nil))
        #expect(unknown.values == ["-Djava.net.useSystemProxies=true"] && unknown.collector == nil && unknown.notes == [.capabilitiesUnknown])
        // OpenJ9 lists no HotSpot flags at all.
        let openJ9 = tune(21, memory: try manual(8192), workload: pack, capabilities: .some(JavaCapabilities(flags: [:])))
        #expect(openJ9.values == ["-Djava.net.useSystemProxies=true"] && openJ9.collector == nil)
        let off = tune(21, memory: try manual(8192), workload: pack, mode: .off)
        #expect(off.values.isEmpty && off.notes == [.disabled])
    }

    @Test func compatibilityOptionsFollowLoaderAndJava() throws {
        let legacy = MemoryWorkload(gameVersion: "1.12.2", loader: .forge, modCount: 20)
        #expect(tune(8, memory: try manual(4096), workload: legacy).values.contains("-Dfml.ignoreInvalidMinecraftCertificates=true"))
        #expect(!tune(17, memory: try manual(4096), workload: .init(gameVersion: "1.20.1", loader: .forge)).values.contains { $0.hasPrefix("-Dfml.") })
        #expect(tune(24, memory: try manual(4096), workload: vanilla).values.contains("--sun-misc-unsafe-memory-access=allow"))
        #expect(!tune(21, memory: try manual(4096), workload: vanilla).values.contains { $0.hasPrefix("--sun-misc") })
        var refused = Self.runtime(25); refused.unsafeMemoryAccessOption = false
        #expect(!tune(25, memory: try manual(4096), workload: vanilla, capabilities: .some(refused)).values.contains { $0.hasPrefix("--sun-misc") })
    }

    @Test func experimentalModeAddsOnlyProductCompactHeaders() throws {
        #expect(tune(25, memory: try manual(4096), workload: vanilla, mode: .experimental).values.contains("-XX:+UseCompactObjectHeaders"))
        #expect(!tune(25, memory: try manual(4096), workload: vanilla).values.contains("-XX:+UseCompactObjectHeaders"))
        #expect(!tune(24, memory: try manual(4096), workload: vanilla, mode: .experimental).values.contains("-XX:+UseCompactObjectHeaders"))
    }

    @Test func probeFallsBackWhenTheRuntimeRefusesTheUnsafeOption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-java-probe-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let java = root.appendingPathComponent("java")
        try """
        #!/bin/sh
        for argument in "$@"; do [ "$argument" = "--sun-misc-unsafe-memory-access=allow" ] && { echo "Unrecognized option: $argument"; exit 1; }; done
        echo "     bool UseG1GC                                   = true                                      {product} {ergonomic}"
        """.write(to: java, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        let probed = try #require(JavaCapabilities.probe(java, major: 25))
        #expect(probed.flags == ["UseG1GC": .product] && !probed.unsafeMemoryAccessOption)
        #expect(JavaCapabilities.probe(root.appendingPathComponent("missing"), major: 21) == nil)
    }

    @Test func launchPlansCarryTheTuningAndKeepUserArgumentsLast() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-tuning-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Tuned", gameVersion: "1.0"); instance.extraJVMArguments = "-XX:MaxGCPauseMillis=30"
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"1.0","mainClass":"Main","libraries":[],"minecraftArguments":"--username ${auth_player_name}"}"#.utf8))
        let jar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("fixture".utf8).write(to: jar)
        let java = JavaRuntime(path: "/test/java", version: "21.0.1", major: 21, architecture: "x86_64", vendor: "Test")
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths, capabilities: Self.runtime(21))
        #expect(plan.tuning?.collector == .g1 && plan.arguments.filter { $0.hasPrefix("-XX:MaxGCPauseMillis") } == ["-XX:MaxGCPauseMillis=30"])
        let g1 = try #require(plan.arguments.firstIndex(of: "-XX:+UseG1GC")), main = try #require(plan.arguments.firstIndex(of: "Main"))
        #expect(g1 < plan.arguments.firstIndex(of: "-XX:MaxGCPauseMillis=30")! && g1 < main)
        instance.jvmTuning = .off
        let off = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths, capabilities: Self.runtime(21))
        #expect(off.tuning?.values == [] && !off.arguments.contains("-XX:+UseG1GC"))
        let legacyJava = JavaRuntime(path: "/test/java", version: "1.8.0_51", major: 8, architecture: "x86_64", vendor: "Test")
        let legacy = try LaunchBuilder.build(instance: instance, manifest: manifest, java: legacyJava, account: Account(username: "Player"), paths: paths)
        #expect(legacy.arguments.contains("-Dcom.sun.jndi.ldap.object.trustURLCodebase=false"))
    }

    @Test func settingInheritsLikeTheOtherLaunchSettings() throws {
        var settings = AppSettings()
        #expect(settings.defaultLaunchSettings.jvmTuning == .recommended)
        settings.defaultJVMTuning = .off
        var instance = GameInstance(name: "Inherits", gameVersion: "1.0"); instance.launchOverrides = .init()
        #expect(try instance.launchSnapshot(defaults: settings).jvmTuning == .off)
        instance.launchOverrides?.jvmTuning = .experimental
        #expect(try instance.launchSnapshot(defaults: settings).jvmTuning == .experimental)
        let decoded = try JSONDecoder().decode(LaunchSettingsValues.self, from: Data("{}".utf8))
        #expect(decoded.jvmTuning == .recommended)
        #expect(ConfigurationService.launchValues(settings.defaultLaunchSettings)["jvmTuning"] == .string("off"))
        #expect(try ConfigurationService.decodeLaunch(ConfigurationService.launchValues(settings.defaultLaunchSettings)).jvmTuning == .off)
    }

    @Test func previewContextSelectsTheJavaALaunchWouldAndFollowsManifestChanges() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-tuning-preview-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Preview", gameVersion: "1.20.1")
        let runtimes = [JavaRuntime(path: "/test/java17", version: "17.0.1", major: 17, architecture: "x86_64", vendor: "Test"),
                        JavaRuntime(path: "/test/java21", version: "21.0.1", major: 21, architecture: "x86_64", vendor: "Test")]
        #expect(await JVMRuntimeContext.preview(instance: instance, java: .automatic, paths: paths, runtimes: runtimes) == .init())
        let manifest = paths.manifest(instance.id)
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"id":"1.20.1","mainClass":"Main","libraries":[],"javaVersion":{"majorVersion":17}}"#.utf8).write(to: manifest)
        #expect(await JVMRuntimeContext.preview(instance: instance, java: .automatic, paths: paths, runtimes: runtimes).java?.major == 17)
        #expect(await JVMRuntimeContext.preview(instance: instance, java: .major(21), paths: paths, runtimes: runtimes).java?.major == 21)
        // A rewritten manifest is read again rather than served from the cache.
        try Data(#"{"id":"1.20.1","mainClass":"Main","libraries":[],"javaVersion":{"majorVersion":21},"type":"release"}"#.utf8).write(to: manifest)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: manifest.path)
        #expect(await JVMRuntimeContext.preview(instance: instance, java: .automatic, paths: paths, runtimes: runtimes).java?.major == 21)
    }

    @Test func settingsPlanIsTheLaunchPlan() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-tuning-plan-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Pack", gameVersion: "1.20.1", loader: .fabric); instance.launchOverrides = .init()
        let settings = AppSettings(), java = JavaRuntime(path: "/test/java", version: "21.0.1", major: 21, architecture: "x86_64", vendor: "Test")
        let values = instance.resolvedLaunchSettings(defaults: settings)
        let shown = try JVMPlan.make(base: values.memory.resolve(availability: roomy, workload: pack), mode: values.jvmTuning, java: java, capabilities: Self.runtime(21),
                                     workload: pack, availability: roomy, userArguments: [])
        #expect(shown.tuning.collector == .z && shown.memory.maximumMB == shown.tuning.heapRaisedToMB)
        let frozen = try instance.launchSnapshot(defaults: settings, availability: roomy, workload: pack)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"1.20.1","mainClass":"Main","libraries":[],"minecraftArguments":"--username ${auth_player_name}"}"#.utf8))
        let jar = paths.versions.appendingPathComponent("1.20.1/1.20.1.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("fixture".utf8).write(to: jar)
        let launched = try LaunchBuilder.build(instance: frozen, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths, capabilities: Self.runtime(21))
        #expect(launched.memory == shown.memory && launched.tuning == shown.tuning)
        #expect(launched.arguments.contains("-Xmx\(shown.memory.maximumMB)M"))
    }

    @Test func probesSurviveTheLauncherProcess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-java-cache-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let java = root.appendingPathComponent("java"), counter = root.appendingPathComponent("runs")
        try """
        #!/bin/sh
        echo run >> "\(counter.path)"
        echo "     bool UseG1GC                                   = true                                      {product} {ergonomic}"
        """.write(to: java, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        let runtime = JavaRuntime(path: java.path, version: "17.0.\(Int.random(in: 1...999_999))", major: 17, architecture: "x86_64", vendor: "Test")
        let cache = root.appendingPathComponent("cache")
        #expect(await JavaCapabilities.load(for: runtime, cache: cache)?.flags == ["UseG1GC": .product])
        // A new process starts with an empty memory cache but finds the file.
        let key = JavaCapabilitiesCache.Key(path: java.resolvingSymlinksInPath().path, version: runtime.version,
                                            stamp: try java.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!.timeIntervalSinceReferenceDate)
        #expect(JavaCapabilitiesCache.read(cache.appendingPathComponent("java-capabilities.json"))[key.path]?.key == key)
        #expect(try String(contentsOf: counter, encoding: .utf8).split(separator: "\n").count == 1)
    }
}
