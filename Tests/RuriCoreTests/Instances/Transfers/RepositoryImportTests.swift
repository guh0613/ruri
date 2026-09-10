import Foundation
import Testing
@testable import RuriCore

@Suite struct RepositoryImportTests {
    private struct Fixture {
        let root: URL
        let paths: LauncherPaths
        let repository: URL
        let source: URL
        let directoryID: UUID
    }
    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-repository-import-" + UUID().uuidString)
        let repository = root.appendingPathComponent("Minecraft"), source = root.appendingPathComponent("Pack")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("minecraft/config"), withIntermediateDirectories: true)
        try Data("pack settings".utf8).write(to: source.appendingPathComponent("minecraft/config/example.txt"))
        try Data("shared settings".utf8).write(to: repository.appendingPathComponent("options.txt"))
        let instance = GameInstance(name: "My Pack", gameVersion: "1.21.1")
        try JSONEncoder().encode(PortableInstance(instance)).write(to: source.appendingPathComponent("ruri-instance.json"))
        let paths = LauncherPaths(root: root.appendingPathComponent("Ruri"))
        let state = try MinecraftFolderStore.add(name: "Games", url: repository, paths: paths)
        return .init(root: root, paths: paths.configured(with: state), repository: repository, source: source, directoryID: state.selectedDirectoryID!)
    }
    private static func installed(_ instance: GameInstance, at paths: LauncherPaths) throws -> GameInstance {
        try paths.prepareInstance(instance.id)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let manifest = VersionManifest(id: instance.repositoryVersionID!, mainClass: "example.Main", jar: instance.repositoryVersionID, libraries: [])
        try JSONEncoder().encode(manifest).write(to: paths.manifest(instance.id))
        try Data("client bytes".utf8).write(to: paths.clientJar(instance.repositoryVersionID!, instance: instance))
        var result = instance; result.installed = true; return result
    }

    @Test func importsIntoSelectedRepositoryAndPublishesOneProfile() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = InstanceTransfer(paths: fixture.paths), prepared = try await service.prepare(fixture.source)
        let result = try await service.install(prepared, name: "My Pack", installing: { instance, paths in
            #expect(paths.game(instance.id).path.contains("/.ruri/imports/"))
            #expect(try paths.resources(for: instance).libraries.path == fixture.repository.appendingPathComponent("libraries").path)
            #expect(!FileManager.default.fileExists(atPath: fixture.repository.appendingPathComponent("versions/My Pack").path))
            #expect(try MinecraftFolderStore.refresh(fixture.directoryID, paths: fixture.paths).instances.isEmpty)
            return try Self.installed(instance, at: paths)
        })
        let state = try StateStore.load(fixture.paths), current = fixture.paths.configured(with: state)
        #expect(state.instances == [result] && state.selectedInstanceID == result.id)
        #expect(result.runDirectory == .isolated && result.repositoryVersionID == "My Pack")
        #expect(try String(contentsOf: current.game(result.id).appendingPathComponent("config/example.txt"), encoding: .utf8) == "pack settings")
        #expect(try String(contentsOf: fixture.repository.appendingPathComponent("options.txt"), encoding: .utf8) == "shared settings")
        #expect(FileManager.default.fileExists(atPath: current.versionDirectory(result.id).appendingPathComponent("My Pack.jar").path))
        #expect(try RepositoryImportStore.pending(directoryID: fixture.directoryID, paths: fixture.paths).isEmpty)
        #expect(try MinecraftFolderStore.refresh(fixture.directoryID, paths: fixture.paths).instances.map(\.id) == [result.id])
        let moved = fixture.root.appendingPathComponent("Moved Minecraft")
        try FileManager.default.moveItem(at: fixture.repository, to: moved)
        let relocated = try GameDirectoryStore.relocate(fixture.directoryID, to: moved, paths: fixture.paths)
        #expect(relocated.gameDirectories?.first?.url.path == moved.path)
        await service.discard(prepared)
    }

    @Test func failedInstallRetainsSourceAndWorkingFilesWithoutPublishing() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = InstanceTransfer(paths: fixture.paths), prepared = try await service.prepare(fixture.source)
        do {
            _ = try await service.install(prepared, name: "My Pack", installing: { _, _ in throw CancellationError() })
            Issue.record("Import should have been cancelled")
        } catch let error as RepositoryImportFailure {
            let kept = try #require(error.preservedFiles)
            #expect(try String(contentsOf: kept.appendingPathComponent("version/config/example.txt"), encoding: .utf8) == "pack settings")
        }
        #expect(try StateStore.load(fixture.paths).instances.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.repository.appendingPathComponent("versions/My Pack").path))
        #expect(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("minecraft/config/example.txt").path))
        #expect(try RepositoryImportStore.pending(directoryID: fixture.directoryID, paths: fixture.paths).isEmpty)
        await service.discard(prepared)
    }

    @Test func aLateNameCollisionNeverReplacesTheOtherVersion() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = InstanceTransfer(paths: fixture.paths), prepared = try await service.prepare(fixture.source)
        let other = fixture.repository.appendingPathComponent("versions/My Pack")
        await #expect(throws: RepositoryImportFailure.self) {
            try await service.install(prepared, name: "My Pack", installing: { instance, paths in
                let result = try Self.installed(instance, at: paths)
                try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
                try Data("other version".utf8).write(to: other.appendingPathComponent("keep.txt"))
                return result
            })
        }
        #expect(try String(contentsOf: other.appendingPathComponent("keep.txt"), encoding: .utf8) == "other version")
        #expect(try FileManager.default.contentsOfDirectory(atPath: other.path) == ["keep.txt"])
        #expect(try StateStore.load(fixture.paths).instances.isEmpty)
        #expect(try RepositoryImportStore.pending(directoryID: fixture.directoryID, paths: fixture.paths).isEmpty)
        await service.discard(prepared)
    }

    @Test func interruptedInstallationCanBePreservedAfterItsLockIsReleased() throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        var instance = GameInstance(name: "Interrupted", gameVersion: "1.21.1")
        instance.directoryID = fixture.directoryID; instance.runDirectory = .isolated
        instance = try MinecraftFolderStore.preparingNewInstance(instance, paths: fixture.paths)
        var transaction: RepositoryImportTransaction? = try .init(instance: instance, paths: fixture.paths)
        _ = try Self.installed(instance, at: transaction!.staging)
        // ExFAT publication creates the destination before copying its marker.
        let publishing = fixture.repository.appendingPathComponent("versions/Interrupted")
        try FileManager.default.createDirectory(at: publishing, withIntermediateDirectories: true)
        #expect(try MinecraftFolderStore.refresh(fixture.directoryID, paths: fixture.paths).instances.isEmpty)
        try FileManager.default.removeItem(at: publishing)
        #expect(throws: (any Error).self) { try GameDirectoryStore.remove(fixture.directoryID, paths: fixture.paths) }
        #expect(throws: (any Error).self) { try RepositoryImportStore.recover(instance.id, directoryID: fixture.directoryID, finish: false, paths: fixture.paths) }
        withExtendedLifetime(transaction) {}; transaction = nil
        let kept = try #require(try RepositoryImportStore.recover(instance.id, directoryID: fixture.directoryID, finish: false, paths: fixture.paths))
        #expect(FileManager.default.fileExists(atPath: kept.appendingPathComponent("version/Interrupted.jar").path))
        #expect(try RepositoryImportStore.pending(directoryID: fixture.directoryID, paths: fixture.paths).isEmpty)
    }

    @Test func publishedImportRecoversItsOriginalIdentityAndClearsDiscoveryMarker() throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        var instance = GameInstance(name: "Published", gameVersion: "1.21.1")
        instance.directoryID = fixture.directoryID; instance.runDirectory = .isolated
        instance = try MinecraftFolderStore.preparingNewInstance(instance, paths: fixture.paths)
        var transaction: RepositoryImportTransaction? = try .init(instance: instance, paths: fixture.paths)
        let result = try Self.installed(instance, at: transaction!.staging)
        try transaction!.publishFiles(result)
        #expect(try MinecraftFolderStore.refresh(fixture.directoryID, paths: fixture.paths).instances.isEmpty)
        #expect(try RepositoryImportStore.pending(directoryID: fixture.directoryID, paths: fixture.paths).first?.canFinish == true)
        withExtendedLifetime(transaction) {}; transaction = nil
        #expect(try RepositoryImportStore.recover(instance.id, directoryID: fixture.directoryID, finish: true, paths: fixture.paths) == nil)
        let state = try StateStore.load(fixture.paths)
        #expect(state.instances == [result])
        #expect(try MinecraftFolderStore.refresh(fixture.directoryID, paths: fixture.paths).instances.map(\.id) == [result.id])
        #expect(try RepositoryImportStore.pending(directoryID: fixture.directoryID, paths: fixture.paths).isEmpty)
    }
}
