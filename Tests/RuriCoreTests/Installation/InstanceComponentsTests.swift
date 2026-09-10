import Foundation
import Testing
@testable import RuriCore

struct InstanceComponentsTests {
    private func fixture(_ layout: String) throws -> (LauncherPaths, GameInstance, URL) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-components-\(UUID())/Ruri"))
        try paths.prepare()
        var instance = GameInstance(name: "Keep", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.15.0")
        instance.installed = true; instance.playTime = 120
        if layout == "repository" {
            let root = paths.root.deletingLastPathComponent().appendingPathComponent("Minecraft"), folder = root.appendingPathComponent("versions/Profile")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(#"{"id":"Profile","clientVersion":"1.21.1","mainClass":"OldMain","libraries":[],"patches":[{"id":"fabric","version":"0.15.0"}]}"#.utf8).write(to: folder.appendingPathComponent("Profile.json"))
            let added = try MinecraftFolderStore.add(name: "Minecraft", url: root, paths: paths)
            instance = try #require(added.instances.first); instance.runDirectory = .isolated; instance.playTime = 120
        } else if layout == "imported" {
            instance.importedInstallation = .init(sourceVersionID: "Local", components: [.init(name: "Fabric", version: "0.15.0")])
        }
        var state = try StateStore.load(paths); state.instances = [instance]; try StateStore.save(state, to: paths)
        let configured = paths.configured(with: state)
        try configured.prepareInstance(instance.id)
        if layout != "repository" {
            try Data(#"{"id":"1.21.1","mainClass":"OldMain","libraries":[]}"#.utf8).write(to: configured.manifest(instance.id))
        }
        let jar = try configured.clientJar(instance.repositoryVersionID ?? "1.21.1", instance: instance)
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original custom client".utf8).write(to: jar)
        try FileManager.default.createDirectory(at: configured.game(instance.id), withIntermediateDirectories: true)
        try Data("keep game data".utf8).write(to: configured.game(instance.id).appendingPathComponent("options.txt"))
        return (configured, instance, jar)
    }

    private static func install(_ candidate: GameInstance, at paths: LauncherPaths) throws -> GameInstance {
        try paths.prepare(); try paths.prepareInstance(candidate.id)
        let library = paths.libraries.appendingPathComponent("org/quiltmc/quilt-loader/0.26.0/quilt-loader-0.26.0.jar")
        try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("new loader".utf8).write(to: library)
        let manifest = candidate.loader == .vanilla
            ? #"{"id":"1.21.1","mainClass":"net.minecraft.client.main.Main","libraries":[]}"#
            : #"{"id":"quilt","mainClass":"QuiltMain","libraries":[{"name":"org.quiltmc:quilt-loader:0.26.0"}]}"#
        try Data(manifest.utf8).write(to: paths.manifest(candidate.id))
        var result = candidate; result.installed = true; return result
    }

    @Test(arguments: ["managed", "repository", "imported"])
    func changesAndRemovesLoaderWhilePreservingInstanceThenRestores(_ layout: String) async throws {
        let (paths, original, client) = try fixture(layout)
        defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let originalJSON = try Data(contentsOf: paths.manifest(original.id))
        let service = InstanceComponents(paths: paths)
        let changed = try await service.change(original, to: .quilt, version: "0.26.0", installing: { candidate, location in
            try StateStore.update(paths) { state in
                state.instances[0].name = "Edited during installation"; state.instances[0].memoryMB = 6144
            }
            return try Self.install(candidate, at: location)
        })
        let instance = try #require(changed.instances.first)
        #expect(instance.id == original.id && instance.loader == .quilt && instance.loaderVersion == "0.26.0")
        #expect(instance.name == "Edited during installation" && instance.memoryMB == 6144 && instance.playTime == 120)
        #expect(try Data(contentsOf: client) == Data("original custom client".utf8))
        #expect(try Data(contentsOf: paths.game(original.id).appendingPathComponent("options.txt")) == Data("keep game data".utf8))
        let active = try await GameInstaller(paths: paths).loadManifest(instance)
        let java = JavaRuntime(path: "/test/java", version: "21", major: 21, architecture: GameInstaller.architecture(for: active), vendor: "Test")
        let plan = try LaunchBuilder.build(instance: instance, manifest: active, java: java, account: Account(username: "Player"), paths: paths)
        #expect(plan.arguments.contains("QuiltMain"))
        let cp = try #require(plan.arguments.firstIndex(of: "-cp"))
        #expect(plan.arguments[cp + 1].contains(client.resolvingSymlinksInPath().path))
        if let directory = instance.directoryID {
            #expect(try MinecraftFolderStore.refresh(directory, paths: paths).instances.first?.loader == .quilt)
        }
        let restored = try await service.restore(instance)
        #expect(restored.instances[0].loader == .fabric && restored.instances[0].name == "Edited during installation")
        #expect(try Data(contentsOf: paths.manifest(original.id)) == originalJSON)
        let removed = try await service.change(restored.instances[0], to: .vanilla, version: nil, installing: { try Self.install($0, at: $1) })
        #expect(removed.instances[0].loader == .vanilla && removed.instances[0].loaderVersion == nil)
        #expect(try await GameInstaller(paths: paths).loadManifest(removed.instances[0]).mainClass == "net.minecraft.client.main.Main")
    }

    @Test func preparationFailureLeavesActiveInstallationAndSettingsIntact() async throws {
        let (paths, original, _) = try fixture("managed")
        defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let before = try Data(contentsOf: paths.manifest(original.id))
        await #expect(throws: (any Error).self) {
            try await InstanceComponents(paths: paths).change(original, to: .forge, version: "test", installing: { _, _ in throw RuriError.message("download failed") })
        }
        #expect(try Data(contentsOf: paths.manifest(original.id)) == before)
        #expect(try StateStore.load(paths).instances.first == original)
    }
}
