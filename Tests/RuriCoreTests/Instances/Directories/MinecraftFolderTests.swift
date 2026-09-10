import Foundation
import Testing
@testable import RuriCore

@Suite struct MinecraftFolderTests {
    private func fixture() throws -> (URL, LauncherPaths, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-folder-tests-" + UUID().uuidString)
        let repository = base.appendingPathComponent("Minecraft")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        return (base, LauncherPaths(root: base.appendingPathComponent("Ruri")), repository)
    }
    private func version(_ name: String, root: URL, extra: [String: Any] = [:]) throws -> URL {
        let directory = root.appendingPathComponent("versions/" + name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var raw: [String: Any] = ["id": name, "mainClass": "example.Main", "libraries": [], "minecraftArguments": "--username ${auth_player_name}"]
        raw.merge(extra) { _, new in new }
        try JSONSerialization.data(withJSONObject: raw).write(to: directory.appendingPathComponent(name + ".json"))
        return directory
    }
    @Test func attachesAllVersionsInPlaceAndPreservesSettingsOnRefresh() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let a = try version("1.21.1", root: root)
        try Data("{}".utf8).write(to: a.appendingPathComponent("modpack.cfg"))
        _ = try version("1.20.1", root: root)
        let original = try Data(contentsOf: a.appendingPathComponent("1.21.1.json"))
        var state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        #expect(state.instances.count == 2)
        let instance = try #require(state.instances.first { $0.repositoryVersionID == "1.21.1" })
        let configured = paths.configured(with: state)
        #expect(configured.game(instance.id).path == a.path)
        #expect(configured.manifest(instance.id) == a.appendingPathComponent("1.21.1.json"))
        #expect(try configured.resources(for: instance).root.path == root.path)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".ruri/instances").path))
        #expect(try Data(contentsOf: a.appendingPathComponent("1.21.1.json")) == original)
        state.instances[state.instances.firstIndex { $0.id == instance.id }!].favorite = true
        _ = try StateStore.save(state, to: paths)
        _ = try version("1.19.4", root: root)
        state = try MinecraftFolderStore.refresh(state.selectedDirectoryID!, paths: paths)
        #expect(state.instances.count == 3)
        #expect(state.instances.first { $0.id == instance.id }?.favorite == true)
        #expect(try MinecraftFolderStore.add(name: "Again", url: root, paths: paths).gameDirectories?.count == 1)
    }
    @Test func switchingFoldersSelectsTheirInstancesAndSupportsEmptyNewFolders() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let first = try MinecraftFolderStore.add(name: "A", url: root, paths: paths)
        let other = base.appendingPathComponent("B"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let second = try MinecraftFolderStore.add(name: "B", url: other, paths: paths)
        #expect(second.selectedInstanceID == nil)
        var input = GameInstance(name: "New Fabric", gameVersion: "1.21.1"); input.directoryID = second.selectedDirectoryID
        let new = try MinecraftFolderStore.preparingNewInstance(input, paths: paths.configured(with: second))
        let target = paths.configured(with: second).including(new)
        #expect(target.game(new.id) == other.appendingPathComponent("versions/New Fabric"))
        #expect(try target.resources(for: new).libraries == other.appendingPathComponent("libraries"))
        let switched = try GameDirectoryStore.select(first.selectedDirectoryID!, paths: paths)
        #expect(switched.selectedInstanceID == first.selectedInstanceID)
        input.name = "1.21.1"; input.directoryID = first.selectedDirectoryID
        #expect(throws: (any Error).self) { try MinecraftFolderStore.preparingNewInstance(input, paths: paths.configured(with: switched)) }
    }
    @Test func loadsFreshInheritedManifestAndLocalLibrariesWithoutCopying() async throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let child = try version("Fabric", root: root, extra: ["inheritsFrom": "1.21.1", "libraries": [["name": "example:helper:1", "hint": "local", "filename": "helper.jar"]]])
        let state = try MinecraftFolderStore.add(name: "Game", url: root, paths: paths)
        let instance = try #require(state.instances.first { $0.repositoryVersionID == "Fabric" })
        let configured = paths.configured(with: state), installer = GameInstaller(paths: paths.configured(with: state))
        let first = try await installer.loadManifest(instance)
        #expect(first.jar == "1.21.1")
        let artifact = try #require(try first.libraries.first?.artifact())
        #expect(try configured.resources(for: instance).libraryFile(artifact) == child.appendingPathComponent("libraries/helper.jar"))
        _ = try version("Fabric", root: root, extra: ["inheritsFrom": "1.21.1", "mainClass": "example.Updated"])
        #expect(try await installer.loadManifest(instance).mainClass == "example.Updated")
        #expect(!FileManager.default.fileExists(atPath: configured.instance(instance.id).path))
    }
    @Test func brokenAndRemovedVersionsStayVisibleWithoutBecomingNewInstallations() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let folder = try version("1.21.1", root: root)
        var state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        try Data("broken".utf8).write(to: folder.appendingPathComponent("1.21.1.json"))
        state = try MinecraftFolderStore.refresh(state.selectedDirectoryID!, paths: paths)
        #expect(state.instances.first?.repositoryIssue != nil)
        #expect(state.instances.first?.installed == true)
        try FileManager.default.removeItem(at: folder)
        state = try MinecraftFolderStore.refresh(state.selectedDirectoryID!, paths: paths)
        #expect(state.instances.first?.repositoryIssue != nil)
        #expect(state.instances.count == 1)
    }
}
