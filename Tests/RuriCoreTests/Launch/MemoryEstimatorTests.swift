import Foundation
import Testing
@testable import RuriCore

struct MemoryEstimatorTests {
    private let roomy = MemoryAvailability(physicalMB: 65536, availableMB: 49152)
    private func estimate(_ workload: MemoryWorkload, on availability: MemoryAvailability? = nil) -> MemoryEstimate {
        MemoryEstimator.estimate(workload: workload, availability: availability ?? roomy)
    }

    @Test func demandGrowsWithVersionLoaderAndMods() {
        #expect(estimate(.init(gameVersion: "1.7.10", loader: .vanilla)).maximumMB == 2048)
        #expect(estimate(.init(gameVersion: "1.16.5", loader: .vanilla)).maximumMB == 2816)
        let vanilla = estimate(.init(gameVersion: "1.21.1", loader: .vanilla))
        #expect(vanilla.demandMB == 2304 && vanilla.generousMB == 3584 && vanilla.maximumMB == 3584 && !vanilla.trimmed)
        #expect(estimate(.init(gameVersion: "24w33a", loader: .vanilla)).maximumMB == 3584)
        // A light Fabric setup: Sodium, Iris and friends.
        let fabric = estimate(.init(gameVersion: "1.21", loader: .fabric, modCount: 30, modBytes: 60 * 1_048_576))
        #expect(fabric.demandMB == 3328 && fabric.maximumMB == 5120 && fabric.initialMB == 2560)
        // A mid-size Forge pack.
        let forge = estimate(.init(gameVersion: "1.20.1", loader: .forge, modCount: 150, modBytes: 600 * 1_048_576))
        #expect(forge.demandMB == 5888 && forge.generousMB == 7936 && forge.maximumMB == 7936 && !forge.constrained)
        // Older packs start lower but still scale with their mod count.
        #expect(estimate(.init(gameVersion: "1.12.2", loader: .forge, modCount: 250, modBytes: 1_288_490_188)).maximumMB == 8192)
        // The marginal mod cost falls; the biggest packs stop short of the automatic cap.
        let kitchenSink = estimate(.init(gameVersion: "1.21.1", loader: .neoforge, modCount: 600, modBytes: 4 * 1_073_741_824))
        #expect(kitchenSink.demandMB == 10496 && kitchenSink.maximumMB == 12544 && kitchenSink.maximumMB <= MemoryEstimator.maximumAutomaticMB)
        #expect(MemoryEstimator.modMB(count: 0) == 0 && MemoryEstimator.modMB(count: 50) == 1000 && MemoryEstimator.modMB(count: 400) == 4600)
    }

    @Test func freeMemoryDecidesTheMarginAndShortfallsAreReported() {
        let pack = MemoryWorkload(gameVersion: "1.20.1", loader: .forge, modCount: 150, modBytes: 600 * 1_048_576)
        let idle = estimate(pack, on: .init(physicalMB: 16384, availableMB: 12288))
        #expect(idle.maximumMB == 7936 && !idle.trimmed)
        // Free memory pays for part of the comfort margin.
        let busy = estimate(pack, on: .init(physicalMB: 16384, availableMB: 8192))
        #expect(busy.maximumMB == 7680 && !busy.constrained && busy.trimmed)
        let cached = estimate(pack, on: .init(physicalMB: 16384, availableMB: 1536))
        #expect(cached.maximumMB == 6144 && !cached.constrained, "reclaimable caches must not shrink the heap below the demand")
        let eightGB = estimate(pack, on: .init(physicalMB: 8192, availableMB: 3072))
        #expect(eightGB.maximumMB == 3072 && eightGB.constrained && eightGB.demandMB == 5888)
        #expect(eightGB.initialMB == 1536 && eightGB.ceilingMB == 3072)
        #expect(estimate(pack, on: .init(physicalMB: 8192)).maximumMB == 4096)
        #expect(estimate(pack, on: .init(physicalMB: 65536, availableMB: 49152)).maximumMB == 7936)
        #expect(estimate(pack, on: .init(physicalMB: 512)).maximumMB == 512)
        let basis = eightGB.basis
        #expect(basis.contains("1.20.1") && basis.contains("Forge") && basis.contains("150") && basis.contains("3072 MB"))
        #expect(!estimate(pack, on: .init(physicalMB: 8192)).basis.contains("剩余"))
    }

    @Test func versionParsingHandlesReleasesPreReleasesAndSnapshots() {
        #expect(MemoryEstimator.minorVersion("1.20.1") == 20)
        #expect(MemoryEstimator.minorVersion("1.21-pre1") == 21)
        #expect(MemoryEstimator.minorVersion("1.7.10") == 7)
        #expect(MemoryEstimator.minorVersion("24w33a") == nil)
        #expect(MemoryEstimator.minorVersion("") == nil)
        #expect(MemoryEstimator.minorVersion("2.0") == nil)
    }

    @Test func scanCountsEnabledModsOnlyAndFlowsIntoSnapshots() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-workload-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Workload", gameVersion: "1.20.1", loader: .forge)
        let game = paths.game(instance.id)
        let fm = FileManager.default
        try fm.createDirectory(at: game.appendingPathComponent("mods/nested"), withIntermediateDirectories: true)
        try Data(count: 3 * 1_048_576).write(to: game.appendingPathComponent("mods/a.jar"))
        try Data(count: 1_048_576).write(to: game.appendingPathComponent("mods/b.JAR"))
        try Data(count: 1_048_576).write(to: game.appendingPathComponent("mods/c.jar.disabled"))
        try Data(count: 1_048_576).write(to: game.appendingPathComponent("mods/readme.txt"))
        try Data(count: 1_048_576).write(to: game.appendingPathComponent("mods/nested/d.jar"))
        var workload = MemoryWorkload.scan(paths: paths, instance: instance)
        #expect(workload == .init(gameVersion: "1.20.1", loader: .forge, modCount: 2, modBytes: 4 * 1_048_576))
        // The cache serves repeat readers until the mods folder changes.
        workload = MemoryWorkload.cached(paths: paths, instance: instance)
        #expect(workload.modCount == 2)
        try Data(count: 1_048_576).write(to: game.appendingPathComponent("mods/e.litemod"))
        // Directory modification stamps have one-second resolution on some file systems.
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: game.appendingPathComponent("mods").path)
        #expect(MemoryWorkload.cached(paths: paths, instance: instance).modCount == 3)
        instance.gameVersion = "1.21.1"
        #expect(MemoryWorkload.cached(paths: paths, instance: instance).gameVersion == "1.21.1")
        let empty = GameInstance(name: "Empty", gameVersion: "1.21.1")
        #expect(MemoryWorkload.scan(paths: paths, instance: empty) == .init(gameVersion: "1.21.1", loader: .vanilla))
        // The estimate flows through settings, previews and launch snapshots.
        var settings = LaunchSettingsValues(); settings.memory = .init(mode: .automatic)
        let preview = try settings.memoryPreview(availability: .init(physicalMB: 32768, availableMB: 20480), workload: workload)
        #expect(preview.estimate?.workload == workload && preview.estimate?.demandMB == 3072 && preview.maximumMB == 4608)
        var defaults = AppSettings(); defaults.defaultMemorySettings = .init(mode: .automatic); instance.launchOverrides = .init()
        let snapshot = try instance.launchSnapshot(defaults: defaults, availability: .init(physicalMB: 32768, availableMB: 20480), workload: workload)
        #expect(snapshot.memoryMB == 4608 && snapshot.frozenMemory?.estimateDetail?.contains("2 个 Mod") == true)
        let encoded = try JSONEncoder().encode(snapshot.frozenMemory)
        #expect(try JSONDecoder().decode(LaunchMemory.self, from: encoded) == snapshot.frozenMemory)
        #expect(try JSONDecoder().decode(LaunchMemory.self, from: Data(#"{"maximumBytes":4294967296,"minimumBytes":536870912,"initialBytes":536870912,"maximumSource":"settings","initialSource":"settings","metaspaceSource":"settings"}"#.utf8)).estimate == nil)
    }
}
