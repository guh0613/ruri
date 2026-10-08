import Foundation
import Testing
@testable import RuriCore

struct GameDirectoryTests {
    @Test(arguments: ["default", "external", "repository"], [GameRunDirectory.isolated, .shared, .custom])
    func launcherAndMonitorResolvePublishedLocations(layout: String, mode: GameRunDirectory) throws {
        let root = URL(fileURLWithPath: "/tmp/ruri location fixture/data")
        let collection = URL(fileURLWithPath: "/tmp/ruri location fixture/collection")
        let custom = CustomRunDirectory(id: UUID(), url: URL(fileURLWithPath: "/tmp/ruri location fixture/custom"), createdAt: .distantPast)
        let directory = GameDirectory(id: UUID(), name: "Collection", url: collection, createdAt: .distantPast,
                                      layout: layout == "repository" ? .minecraft : .managed)
        var instance = GameInstance(name: "Location", gameVersion: "1.21.1")
        instance.directoryID = layout == "default" ? nil : directory.id
        instance.runDirectory = mode; instance.customRunDirectory = mode == .custom ? custom : nil
        instance.repositoryVersionID = layout == "repository" ? "local-version" : nil
        let paths = LauncherPaths(root: root, directories: layout == "default" ? [] : [directory]).including(instance)
        let frozen = try JSONDecoder().decode(SessionLocationSnapshot.self, from: JSONEncoder().encode(SessionLocationSnapshot(paths: paths, instanceID: instance.id)))
        let base = layout == "default" ? root : collection
        let metadata = base.appendingPathComponent("\(layout == "repository" ? ".ruri/instances" : "instances")/\(instance.id)")
        let game: URL
        switch mode {
        case .custom: game = custom.url
        case .shared: game = layout == "repository" ? base : base.appendingPathComponent("minecraft")
        case .isolated: game = layout == "repository" ? base.appendingPathComponent("versions/local-version") : metadata.appendingPathComponent("minecraft")
        }
        let data = mode == .isolated ? metadata : game.appendingPathComponent(".ruri")
        for location in [paths.instance(instance.id), frozen.instance(instance.id)] { #expect(location.path == metadata.path) }
        for location in [paths.game(instance.id), frozen.game(instance.id)] { #expect(location.path == game.path) }
        for location in [paths.gameDataState(instance.id), frozen.gameDataState(instance.id)] { #expect(location.path == data.path) }
        if layout == "repository" {
            let staging = paths.stagingRepositoryImport(instance)
            let workspace = base.appendingPathComponent(".ruri/imports/\(instance.id)")
            #expect(staging.instance(instance.id).path == workspace.appendingPathComponent("metadata").path)
            #expect(staging.versionDirectory(instance.id).path == workspace.appendingPathComponent("version").path)
            #expect(staging.game(instance.id).path == (mode == .isolated ? workspace.appendingPathComponent("version") : game).path)
            #expect(staging.gameDataState(instance.id).path == (mode == .isolated ? workspace.appendingPathComponent("metadata") : data).path)
            let published = SessionLocationSnapshot(paths: staging, instanceID: instance.id)
            #expect(published.instance(instance.id).path == metadata.path && published.game(instance.id).path == game.path)
        }
    }

    private func fixture() throws -> (URL, LauncherPaths, GameDirectory) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-directories-\(UUID())")
        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let paths = LauncherPaths(root: root.appendingPathComponent("app"))
        let directory = try GameDirectory.create(name: "整合包", at: external, paths: paths)
        return (root, paths, directory)
    }

    @Test func selectingADirectoryOnlyChangesWhereNewInstancesAreCreated() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = GameInstance(name: "Old instance", gameVersion: "1.21.1")
        var state = PersistentState(); state.instances = [old]; state.gameDirectories = [directory]; state.selectedDirectoryID = directory.id
        try StateStore.save(state, to: base)
        let paths = try base.configured(with: StateStore.load(base))
        #expect(paths.instance(old.id) == base.instance(old.id))
        let newID = UUID()
        #expect(paths.instance(newID) == directory.url.appendingPathComponent("instances/\(newID)"))
    }

    @Test func missingOrReplacedExternalFolderCannotBeRecreatedByMutation() async throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let instance = GameInstance(name: "External", gameVersion: "1.21.1")
        let paths = LauncherPaths(root: base.root, directories: [directory], instanceDirectories: [instance.id: directory.id])
        try paths.prepareInstance(instance.id)
        try FileManager.default.removeItem(at: directory.url)
        #expect(throws: (any Error).self) { try paths.prepareInstance(instance.id) }
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: instance.id) }
        await #expect(throws: (any Error).self) { try await ContentManager(paths: paths, instanceID: instance.id).recover() }
        await #expect(throws: (any Error).self) { try await WorldManager(paths: paths, instanceID: instance.id).recover() }
        #expect(!FileManager.default.fileExists(atPath: directory.url.path))
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try paths.prepareInstance(instance.id) }
        #expect(!FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("instances").path))
    }

    @Test func registrationRejectsNestedDuplicateAndOccupiedFoldersAndInvalidReferences() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: base.root, directories: [directory])
        #expect(throws: (any Error).self) { try GameDirectory.create(name: "重复", at: directory.url, paths: paths) }
        let nested = directory.url.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try GameDirectory.create(name: "嵌套", at: nested, paths: paths) }
        let occupied = root.appendingPathComponent("existing-minecraft")
        try FileManager.default.createDirectory(at: occupied.appendingPathComponent("versions"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try GameDirectory.create(name: "Existing", at: occupied, paths: paths) }
        #expect(!FileManager.default.fileExists(atPath: occupied.appendingPathComponent(GameDirectory.markerName).path))
        let broken = LauncherPaths(root: base.root, instanceDirectories: [UUID(): UUID()])
        #expect(throws: (any Error).self) { try broken.validateDirectoryConfiguration() }
    }

    @Test func internalSymlinkEscapeIsRejectedBeforeWriting() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.url.appendingPathComponent("instances"), withDestinationURL: outside)
        let paths = LauncherPaths(root: base.root, directories: [directory], newInstanceDirectoryID: directory.id)
        #expect(throws: (any Error).self) { try paths.prepareInstance(UUID()) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func removalKeepsTheFolderReattachableAndRejectsRegisteredOrUnlistedInstances() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var state = PersistentState(); state.gameDirectories = [directory]; state.selectedDirectoryID = directory.id
        try StateStore.save(state, to: base)
        try GameDirectoryStore.remove(directory.id, paths: base)
        #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent(GameDirectory.markerName).path))
        let attached = try GameDirectoryStore.add(name: "Reattached", url: directory.url, paths: base)
        #expect(attached.gameDirectories?.first?.id == directory.id && attached.selectedDirectoryID == directory.id)
        let pending = directory.url.appendingPathComponent("instances/\(UUID())")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try GameDirectoryStore.remove(directory.id, paths: base) }
        try FileManager.default.removeItem(at: pending)
        var instance = GameInstance(name: "Present", gameVersion: "1.21.1"); instance.directoryID = directory.id
        try StateStore.update(base) { $0.instances.append(instance) }
        #expect(throws: (any Error).self) { try GameDirectoryStore.remove(directory.id, paths: base) }
        #expect(try StateStore.load(base).instances == [instance])
    }

    @Test func relocationPreservesContentsAndRejectsWrongFoldersOrOpenLeases() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var instance = GameInstance(name: "Leased", gameVersion: "1.21.1"); instance.directoryID = directory.id
        var state = PersistentState(); state.gameDirectories = [directory]; state.instances = [instance]
        try StateStore.save(state, to: base)
        let paths = base.configured(with: state)
        var lease: GameRunLease? = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        try Data("preserved".utf8).write(to: paths.instance(instance.id).appendingPathComponent("proof.txt"))
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: directory.url, to: moved)
        #expect(throws: (any Error).self) { try GameDirectoryStore.relocate(directory.id, to: moved, paths: base) }
        #expect(try StateStore.load(base).gameDirectories?.first?.url == directory.url)
        withExtendedLifetime(lease) {}; lease = nil
        #expect(throws: (any Error).self) { try GameDirectoryStore.relocate(directory.id, to: root, paths: base) }
        try GameDirectoryStore.relocate(directory.id, to: moved, paths: base)
        #expect(try String(contentsOf: moved.appendingPathComponent("instances/\(instance.id)/proof.txt"), encoding: .utf8) == "preserved")
        #expect(try StateStore.load(base).gameDirectories?.first?.url == moved.standardizedFileURL.resolvingSymlinksInPath())
    }
}
