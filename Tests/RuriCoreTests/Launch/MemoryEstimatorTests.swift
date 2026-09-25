import Foundation
import Testing
@testable import RuriCore

struct MemoryEstimatorTests {
    private let roomy = MemoryAvailability(physicalMB: 65536, availableMB: 49152)
    private func estimate(_ workload: MemoryWorkload, on availability: MemoryAvailability? = nil) -> MemoryEstimate {
        MemoryEstimator.estimate(workload: workload, availability: availability ?? roomy)
    }

    @Test func demandGrowsWithVersionLoaderAndMods() {
        let old = estimate(.init(gameVersion: "1.7.10", loader: .vanilla))
        let current = estimate(.init(gameVersion: "1.21.1", loader: .vanilla))
        let forge = estimate(.init(gameVersion: "1.21.1", loader: .forge))
        let pack = estimate(.init(gameVersion: "1.21.1", loader: .forge, modCount: 150, modBytes: 600 * 1_048_576))
        #expect(old.maximumMB < current.maximumMB)
        #expect(current.maximumMB < forge.maximumMB && forge.maximumMB < pack.maximumMB)
        #expect(estimate(.init(gameVersion: "1.21-pre1", loader: .vanilla)).maximumMB == current.maximumMB)
        #expect(estimate(.init(gameVersion: "24w33a", loader: .vanilla)).maximumMB == current.maximumMB)
        let huge = estimate(.init(gameVersion: "1.21.1", loader: .forge, modCount: 3000))
        #expect(huge.maximumMB <= MemoryEstimator.maximumAutomaticMB)
    }

    @Test func memoryPressureTrimsHeadroomAndReportsHardwareShortfalls() {
        let pack = MemoryWorkload(gameVersion: "1.20.1", loader: .forge, modCount: 150, modBytes: 600 * 1_048_576)
        let idle = estimate(pack, on: .init(physicalMB: 16384, availableMB: 12288))
        let busy = estimate(pack, on: .init(physicalMB: 16384, availableMB: 8192))
        let cached = estimate(pack, on: .init(physicalMB: 16384, availableMB: 1536))
        #expect(!idle.constrained && !idle.trimmed)
        #expect(busy.maximumMB < idle.maximumMB && busy.trimmed && !busy.constrained)
        #expect(cached.maximumMB >= cached.demandMB, "reclaimable caches must not starve the game")
        let small = estimate(pack, on: .init(physicalMB: 8192, availableMB: 3072))
        #expect(small.constrained && small.maximumMB < small.demandMB)
        #expect(small.maximumMB < 8192 && small.initialMB <= small.maximumMB)
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
        let workload = MemoryWorkload.cached(paths: paths, instance: instance)
        #expect(workload == .init(gameVersion: "1.20.1", loader: .forge, modCount: 2, modBytes: 4 * 1_048_576))
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
        var defaults = AppSettings(); defaults.defaultMemorySettings = .init(mode: .automatic); instance.launchOverrides = .init()
        let snapshot = try instance.launchSnapshot(defaults: defaults, availability: .init(physicalMB: 32768, availableMB: 20480), workload: workload)
        #expect(snapshot.memoryMB == preview.maximumMB && snapshot.frozenMemory?.estimate?.workload == workload)
    }
}
