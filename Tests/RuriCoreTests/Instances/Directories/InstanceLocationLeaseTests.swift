import Foundation
import Testing
@testable import RuriCore

struct InstanceLocationLeaseTests {
    @Test func readersCoexistAndAWriterWaitsForAllOtherOperations() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let (paths, id) = (fixture.paths, fixture.source.id)
        var first: InstanceLocationLease? = try .acquire(paths: paths, instanceID: id)
        var second: InstanceLocationLease? = try .acquire(paths: paths, instanceID: id)
        #expect(throws: (any Error).self) { try first?.excludeOtherOperations() }
        #expect(throws: (any Error).self) { try InstanceLocationLease.acquireForMoveRecovery(paths: paths, instanceID: id) }
        withExtendedLifetime(second) {}; second = nil
        try first?.excludeOtherOperations()
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: id) }
        #expect(throws: (any Error).self) { try paths.prepareInstance(id) }
        await #expect(throws: (any Error).self) { try await ContentManager(paths: paths, instanceID: id).records() }
        await #expect(throws: (any Error).self) { try await WorldManager(paths: paths, instanceID: id).worlds() }
        let other = GameInstance(name: "Unrelated", gameVersion: "1.21.1")
        let independent = try InstanceLocationLease.acquire(paths: paths, instanceID: other.id)
        withExtendedLifetime(independent) {}
        withExtendedLifetime(first) {}; first = nil
        #expect(try await ContentManager(paths: paths, instanceID: id).records().isEmpty)
        _ = try await WorldManager(paths: paths, instanceID: id).worlds()
    }

    @Test func stalePathsAndManagersCannotRecreateTheOriginalTree() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let (paths, id) = (fixture.paths, fixture.source.id)
        let content = ContentManager(paths: paths, instanceID: id), worlds = WorldManager(paths: paths, instanceID: id)
        let installer = GameInstaller(paths: paths)
        var owner: GameRunLease? = try .acquire(paths: paths, instanceID: id)
        try owner?.excludeLocationOperations()
        var moved = fixture.source; moved.directoryID = fixture.target.id
        let target = paths.including(moved)
        try FileManager.default.createDirectory(at: target.instance(id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: paths.instance(id), to: target.instance(id))
        let saved = try StateStore.update(paths) { $0.instances[0] = moved }
        #expect(throws: (any Error).self) { try paths.prepareInstance(id) }
        withExtendedLifetime(owner) {}; owner = nil
        #expect(throws: (any Error).self) { try paths.prepareInstance(id) }
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: id) }
        #expect(GameRunLease.isHeld(paths: paths, instanceID: id))
        await #expect(throws: (any Error).self) { try await content.records() }
        await #expect(throws: (any Error).self) { try await worlds.worlds() }
        await #expect(throws: (any Error).self) { try await installer.install(fixture.source) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: paths.instance(id).path))
        let current = paths.configured(with: saved)
        #expect(try await ContentManager(paths: current, instanceID: id).records().isEmpty)
        let currentLease = try GameRunLease.acquire(paths: current, instanceID: id)
        withExtendedLifetime(currentLease) {}
        #expect(!FileManager.default.fileExists(atPath: paths.instance(id).path))
    }

    @Test func moveAccessUpgradesItsExistingRunLeaseAndReleasesAllLocks() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .custom); defer { fixture.cleanup() }
        var access: InstanceMoveAccess? = try await .acquire(instance: fixture.source, paths: fixture.paths)
        #expect(throws: (any Error).self) { try InstanceLocationLease.acquire(paths: fixture.paths, instanceID: fixture.source.id) }
        await #expect(throws: (any Error).self) { try await ContentManager(paths: fixture.paths, instanceID: fixture.source.id).records() }
        withExtendedLifetime(access) {}; access = nil
        _ = try await ContentManager(paths: fixture.paths, instanceID: fixture.source.id).records()
        let lease = try GameRunLease.acquire(paths: fixture.paths, instanceID: fixture.source.id)
        withExtendedLifetime(lease) {}
    }
}
