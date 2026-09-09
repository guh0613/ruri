import Foundation
import Testing
@testable import RuriCore

struct MemorySettingsTests {
    @Test func automaticMemoryReservesHeadroomAndUsesAvailableEstimate() throws {
        let automatic = MemorySettings(mode: .automatic)
        #expect(try automatic.resolve(availability: .init(physicalMB: 65536, availableMB: 49152)).maximumMB == 8192)
        #expect(try automatic.resolve(availability: .init(physicalMB: 16384, availableMB: 12288)).maximumMB == 4096)
        #expect(try automatic.resolve(availability: .init(physicalMB: 16384, availableMB: 2048)).maximumMB == 1024)
        #expect(try automatic.resolve(availability: .init(physicalMB: 4096)).maximumMB == 1024)
        #expect(try automatic.resolve(availability: .init(physicalMB: 4096, availableMB: 200)).maximumMB == 512)
        #expect(throws: (any Error).self) { try automatic.resolve(availability: .init(physicalMB: 0)) }
        let sample = MemoryAvailability.current()
        #expect(sample.physicalMB >= 512)
        #expect(sample.availableMB == nil || sample.availableMB! >= 0)
    }

    @Test func manualInitialAndMetaspaceAndValidation() throws {
        let resolved = try MemorySettings(maximumMB: 6144, initialMB: 1024, metaspaceMB: 512).resolve()
        #expect(resolved.arguments == ["-Xms1024M", "-Xmx6144M", "-XX:MaxMetaspaceSize=512M"])
        #expect(resolved.maximumSource == .settings && resolved.initialBytes == 1_073_741_824)
        #expect(throws: (any Error).self) { try MemorySettings(maximumMB: 512, initialMB: 1024).resolve() }
        #expect(throws: (any Error).self) { try MemorySettings(metaspaceMB: 0).resolve() }
        #expect(try MemorySettings().resolve().metaspaceBytes == nil)
    }

    @Test func aliasesAndUnitsRespectOrderWithoutConflatingInitialAndMinimum() throws {
        let base = try MemorySettings(maximumMB: 4096).resolve()
        let first = try JVMHeapArguments.resolve(base: base, arguments: ["-Xmx2G", "-XX:MaxHeapSize=3072m", "-Xms768m", "-XX:InitialHeapSize=1048576k", "-XX:MaxMetaspaceSize=268435456"])
        #expect(first.maximumMB == 3072 && first.maximumSource == .jvmArguments)
        #expect(first.minimumBytes == 768 * 1_048_576 && first.initialBytes == 1024 * 1_048_576)
        #expect(try #require(first.metaspaceBytes) == Int64(256) * 1_048_576)
        let second = try JVMHeapArguments.resolve(base: base, arguments: ["-XX:InitialHeapSize=1G", "-Xms512m", "-XX:MaxHeapSize=3G", "-Xmx2G"])
        #expect(second.initialBytes == 512 * 1_048_576 && second.maximumMB == 2048)
        let minimum = try JVMHeapArguments.resolve(base: base, arguments: ["-XX:MinHeapSize=128M"])
        #expect(minimum.minimumBytes == 128 * 1_048_576 && minimum.initialBytes == 512 * 1_048_576)
        let unrelated = try JVMHeapArguments.resolve(base: base, arguments: ["-Dmessage=-Xmx16G", "-XX:MaxRAMPercentage=70"])
        #expect(unrelated == base)
    }

    @Test func malformedAndConflictingHeapArgumentsFailBeforeJava() throws {
        let base = try MemorySettings().resolve()
        for flag in ["-Xmx", "-Xmx1.5G", "-Xmx-1G", "-Xmx999999999999999999G", "-XX:MaxHeapSize=1gb", "-Xmx1M", "-Xms5G", "-XX:InitialHeapSize=128M"] {
            #expect(throws: (any Error).self) { try JVMHeapArguments.resolve(base: base, arguments: [flag]) }
        }
    }

    @Test func oldOverrideJSONAndGlobalMemoryEditsKeepManualSemantics() throws {
        let old = try JSONDecoder().decode(InstanceLaunchOverrides.self, from: Data(#"{"memoryMB":6144,"jvmArguments":""}"#.utf8))
        #expect(old.memory == .init(maximumMB: 6144))
        var modern = old; modern.memory?.mode = .automatic; modern.memory?.initialMB = 1024
        #expect(try JSONDecoder().decode(InstanceLaunchOverrides.self, from: JSONEncoder().encode(modern)) == modern)
        var defaults = AppSettings(); defaults.defaultLaunchSettings = .init()
        defaults.defaultMemoryMB = 8192
        #expect(defaults.defaultLaunchSettings.memory == .init(maximumMB: 8192))
        modern.setInheritance(true, for: .memory, defaults: defaults.defaultLaunchSettings)
        #expect(modern.memory == nil && modern.inherits(.memory))
    }

    @MainActor @Test func snapshotFreezesAutomaticMemoryAndSessionSeesArgumentOverride() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-heap-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Heap", gameVersion: "1.0"); instance.launchOverrides = .init()
        var defaults = AppSettings(); defaults.defaultMemorySettings = .init(mode: .automatic); defaults.defaultJVMArguments = "-Xmx2G -Xms1G"
        let snapshot = try instance.launchSnapshot(defaults: defaults, availability: .init(physicalMB: 65536, availableMB: 49152))
        #expect(snapshot.frozenMemory?.maximumMB == 8192 && snapshot.frozenMemory?.maximumSource == .automatic)
        var state = PersistentState(); state.instances = [instance]; state.settings = defaults; try StateStore.save(state, to: paths)
        let recorder = try GameSessionRecorder(paths: paths, instance: snapshot, accountMode: "offline")
        #expect(recorder.record.memoryMB == 2048 && recorder.record.memory?.initialBytes == 1_073_741_824)
        #expect(recorder.record.memory?.maximumSource == .jvmArguments)
        let before = try Data(contentsOf: paths.state)
        #expect(throws: (any Error).self) { try StateStore.update(paths) { $0.instances[0] = snapshot } }
        #expect(try Data(contentsOf: paths.state) == before)
        try recorder.fail(CancellationError(), cancelled: true)
    }

    @Test func exportKeepsInitialHeapAndMetaspaceThroughPortableJVMArguments() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-heap-export-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Heap export", gameVersion: "1.0"); instance.launchOverrides = .init()
        var state = PersistentState(); state.instances = [instance]; state.settings.defaultMemorySettings = .init(maximumMB: 6144, initialMB: 1024, metaspaceMB: 384)
        try StateStore.save(state, to: paths); try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let transfer = InstanceTransfer(paths: paths)
        for format in [InstanceExportFormat.ruri, .multimc, .mcbbs] {
            let zip = paths.cache.appendingPathComponent("\(format.rawValue).zip")
            try await transfer.export(instance, to: zip, format: format)
            let prepared = try await transfer.prepare(zip)
            let memory = try prepared.instance.resolvedLaunchSettings(defaults: AppSettings()).memoryPreview()
            #expect(memory.maximumMB == 6144 && memory.initialBytes == 1_073_741_824)
            #expect(try #require(memory.metaspaceBytes) == Int64(384) * 1_048_576)
            await transfer.discard(prepared)
        }
        await #expect(throws: (any Error).self) { try await transfer.export(instance, to: paths.cache.appendingPathComponent("unsupported.mrpack"), format: .mrpack) }
    }

    @MainActor @Test func invalidHeapStillHasAPreparationFailureRecord() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-invalid-heap-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Invalid heap", gameVersion: "1.0"); instance.extraJVMArguments = "-Xmx1M"
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        do { _ = try instance.launchSnapshot(defaults: AppSettings()); Issue.record("Expected invalid heap") }
        catch { try recorder.fail(error, cancelled: false) }
        let saved = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(saved.state == .failed && saved.processID == nil && saved.failure != nil)
        #expect(saved.memory == nil)
    }

    @Test func concurrentMemoryPolicyEditsCannotCombineIntoDifferentOrInvalidLimits() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-heap-merge-\(UUID())")); defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        var instance = GameInstance(name: "Concurrent memory", gameVersion: "1.0"); instance.launchOverrides = .init()
        instance.launchOverrides?.memory = .init(maximumMB: 4096, initialMB: 512)
        var legacy = PersistentState(); legacy.schemaVersion = 5; legacy.instances = [instance]
        // Start at the previous format without structured global memory.
        try JSONEncoder().encode(legacy).write(to: paths.state)
        let baseline = try StateStore.load(paths)
        var local = baseline; local.settings.defaultMemorySettings = .init(mode: .automatic)
        try StateStore.update(paths) { $0.settings.defaultMemoryMB = 8192 }
        var bytes = try Data(contentsOf: paths.state)
        #expect(throws: (any Error).self) { try StateStore.save(local, to: paths, basedOn: baseline) }
        #expect(try Data(contentsOf: paths.state) == bytes)
        let next = try StateStore.load(paths)
        #expect(next.settings.defaultMemorySettings == .init(maximumMB: 8192))
        var smaller = next; smaller.instances[0].launchOverrides?.memory?.maximumMB = 1024
        try StateStore.update(paths) { $0.instances[0].launchOverrides?.memory?.initialMB = 2048 }
        bytes = try Data(contentsOf: paths.state)
        #expect(throws: (any Error).self) { try StateStore.save(smaller, to: paths, basedOn: next) }
        #expect(try Data(contentsOf: paths.state) == bytes)
    }
}
