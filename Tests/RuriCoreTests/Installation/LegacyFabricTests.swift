import Foundation
import Testing
@testable import RuriCore

struct LegacyFabricTests {
    private let libraries: [[String: String]] = [
        ["name": "net.fabricmc:fabric-loader:0.19.3", "url": "https://maven.fabricmc.net/"],
        ["name": "net.legacyfabric:intermediary:1.8.9", "url": "https://maven.legacyfabric.net/"],
        ["name": "org.lwjgl.lwjgl:lwjgl:2.9.4+legacyfabric.17", "url": "https://maven.legacyfabric.net/"]
    ]
    @Test func legacyNativeDeclarationDownloadsOnlyItsPlatformClassifier() throws {
        let library = try JSONDecoder().decode(Library.self, from: Data(#"{"name":"org.lwjgl.lwjgl:lwjgl-platform:2.9.4+legacyfabric.17","url":"https://maven.legacyfabric.net/","natives":{"osx":"natives-osx"},"extract":{"exclude":["META-INF/"]}}"#.utf8))
        #expect(try library.artifact() == nil)
        let resolved = try library.nativeArtifact(architecture: "x86_64")
        let native = try #require(resolved)
        #expect(native.url?.lastPathComponent == "lwjgl-platform-2.9.4+legacyfabric.17-natives-osx.jar")
        #expect(native.path?.hasSuffix("-natives-osx.jar") == true)
        var explicit = library
        explicit.downloads = .init(artifact: Artifact(url: URL(string: "https://example.test/common.jar")), classifiers: ["natives-osx": native])
        #expect(try explicit.artifact()?.url?.lastPathComponent == "common.jar")
        #expect(try explicit.nativeArtifact(architecture: "x86_64") == native)
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Legacy native", gameVersion: "1.8.9", loader: .legacyfabric, loaderVersion: "0.19.3")
        instance.installed = true
        try paths.prepare(); try paths.prepareInstance(instance.id)
        let client = try paths.clientJar(instance.gameVersion, instance: instance)
        let nativeFile = paths.libraries.appendingPathComponent(native.path!)
        for file in [client, nativeFile] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: file)
        }
        let manifest = VersionManifest(id: "1.8.9", mainClass: "Main", libraries: [library])
        try JSONEncoder().encode(manifest).write(to: paths.manifest(instance.id))
        let copy = PreparedMinecraftInstallation.portableCopy(instance)
        let plan = try MinecraftInstallationCopy.read(instance: instance, copy: copy, paths: paths, portable: true)
        let copied = try JSONDecoder().decode(VersionManifest.self, from: plan.manifest)
        #expect(copied.libraries[0].downloads?.classifiers?["natives-osx"]?.sha1 != nil)
        #expect(plan.resources.contains { $0.path.hasSuffix("-natives-osx.jar") })
    }
    @Test func repositoryRecognizesModernAndOlderLegacyLoaderCoordinates() throws {
        let helper = HMCLPackTests(), (paths, source) = try helper.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        for (name, libs) in [("Modern", libraries), ("Older", [["name": "net.legacyfabric:fabric-loader:0.14.25"]])] {
            try helper.json(["id": name, "clientVersion": "1.8.9", "mainClass": "net.fabricmc.loader.impl.launch.knot.KnotClient", "libraries": libs], to: "versions/\(name)/\(name).json", in: source)
        }
        let application = LauncherPaths(root: paths.root.appendingPathComponent("launcher"))
        let state = try MinecraftFolderStore.add(name: "Legacy games", url: source, paths: application)
        #expect(state.instances.count == 2)
        #expect(state.instances.allSatisfy { $0.loader == .legacyfabric && $0.gameVersion == "1.8.9" })
        let modern = try #require(state.instances.first { $0.repositoryVersionID == "Modern" })
        #expect(modern.repositoryComponents == [.init(name: "Legacy Fabric", version: "0.19.3")])
        #expect(InstanceComponents.unavailableReason(modern) == nil)
        #expect(modern.loader.modrinthLoader == "legacy-fabric")
        #expect(try LoaderEndpoints.profile(loader: .legacyfabric, game: "1.8.9", version: "0.19.3").absoluteString == "https://meta.legacyfabric.net/v2/versions/loader/1.8.9/0.19.3/profile/json")
        #expect(try LoaderEndpoints.versions(loader: .legacyfabric, game: "2.0_Red").lastPathComponent == "2point0_Red")
    }

    @Test func importsHMCLAndRoundTripsSupportedPortableFormats() async throws {
        let helper = HMCLPackTests(), (paths, source) = try helper.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try helper.json(["name": "Legacy pack", "gameVersion": "1.8.9"], to: "modpack.json", in: source)
        try helper.json(["jar": "1.8.9", "libraries": libraries, "patches": [["id": "fabric", "version": "0.19.3"]]], to: "minecraft/pack.json", in: source)
        try helper.write(Data("options".utf8), to: "minecraft/options.txt", in: source)
        let transfer = InstanceTransfer(paths: paths), prepared = try await transfer.prepare(source)
        #expect(prepared.instance.loader == .legacyfabric && prepared.instance.loaderVersion == "0.19.3")
        let imported = try await transfer.install(prepared, name: "Legacy pack") { $0 }
        await transfer.discard(prepared)
        #expect(try Data(contentsOf: paths.game(imported.id).appendingPathComponent("options.txt")) == Data("options".utf8))
        for format in [InstanceExportFormat.ruri, .mcbbs] {
            let output = paths.cache.appendingPathComponent(format.rawValue + ".zip")
            try await transfer.export(imported, to: output, format: format)
            let restored = try await transfer.prepare(output)
            #expect(restored.instance.loader == .legacyfabric && restored.instance.loaderVersion == "0.19.3")
            await transfer.discard(restored)
        }
        let output = paths.cache.appendingPathComponent("unsupported.zip")
        await #expect(throws: (any Error).self) { try await transfer.export(imported, to: output, format: .multimc) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
}
