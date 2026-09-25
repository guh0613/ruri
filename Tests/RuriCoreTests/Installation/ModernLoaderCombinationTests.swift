import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct ModernLoaderCombinationTests {
    @Test(arguments: ["0.1.16", "0.1.17"])
    func bootstrapIgnoresOnlyItsOwnLibrariesAndClient(_ version: String) {
        let client = URL(fileURLWithPath: "/games/asm/profile.jar")
        let classpath = ["/games/asm/libraries/asm-9.1.jar", "/games/asm/libraries/OptiFine-combined.jar", client.path]
        let manifest = VersionManifest(id: "profile", mainClass: "cpw.mods.bootstraplauncher.BootstrapLauncher",
            libraries: [Library(name: "cpw.mods:bootstraplauncher:" + version, downloads: nil, rules: nil, natives: nil, extract: nil)])
        let result = ForgeLaunchArguments.bootstrap(["-DignoreList=asm,bootstraplauncher", "-cp", "classpath"], manifest: manifest, classpath: classpath, client: client)
        if version == "0.1.16" {
            #expect(result[0] == "-DignoreList=/games/asm/profile.jar,/games/asm/libraries/asm-9.1.jar")
        } else { #expect(result[0] == "-DignoreList=asm,bootstraplauncher,profile.jar") }
        #expect(!result[0].contains("OptiFine"))
        #expect(result.suffix(2) == ["-cp", "classpath"])
    }

    private func package(at file: URL, build: String = "20231221-120401", modern: Bool = true) throws {
        var data = Data([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 52, 0, 12])
        func number(_ value: Int, _ bytes: Int = 2) { for shift in (0..<bytes).reversed() { data.append(UInt8((value >> (shift * 8)) & 255)) } }
        func text(_ value: String) { data.append(1); number(value.utf8.count); data.append(contentsOf: value.utf8) }
        text("MC_VERSION"); text("Ljava/lang/String;"); text("ConstantValue"); text("1.20.1")
        data.append(8); number(4)
        text("OF_EDITION"); text("HD_U"); data.append(8); number(7)
        text("OF_RELEASE"); text("I6"); data.append(8); number(10)
        number(0); number(0); number(0); number(0); number(3)
        for (name, value) in [(1, 5), (6, 8), (9, 11)] {
            number(0); number(name); number(2); number(1); number(3); number(2, 4); number(value)
        }
        let archive = try Archive(url: file, accessMode: .create)
        var entries = ["Config.class": data, "buildof.txt": Data(build.utf8), "META-INF/mods.toml": Data("modId=optifine".utf8),
                       "optifine/OptiFineForgeTweaker.class": Data("legacy".utf8)]
        if modern {
            entries["META-INF/services/cpw.mods.modlauncher.api.ITransformationService"] = Data("# transformation provider\noptifine.OptiFineTransformationService\n".utf8)
            entries["optifine/OptiFineTransformationService.class"] = Data("modern".utf8)
        }
        for (name, bytes) in entries.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(bytes.count)) { offset, count in bytes.subdata(in: Int(offset)..<(Int(offset) + count)) }
        }
    }

    @Test(arguments: ["cpw.mods.modlauncher.Launcher", "cpw.mods.bootstraplauncher.BootstrapLauncher", "net.minecraftforge.bootstrap.ForgeBootstrap"])
    func modernProfilesPreserveForgeAndRepairTheirTransformationArchive(_ main: String) async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-modern-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let file = paths.cache.appendingPathComponent("original.jar")
        try package(at: file)
        let originalHash = try InstanceTransfer.sha1(file)
        let installer = OptiFineInstaller(paths: paths, downloader: DownloadManager())
        var instance = GameInstance(name: "Modern combination", gameVersion: "1.20.1")
        instance.setLoaderSelections([.init(loader: .forge, version: "47.2.18"), .init(loader: .optifine, version: "HD_U_I6")])
        try paths.prepareInstance(instance.id)
        var base = VersionManifest(id: "1.20.1", mainClass: main, libraries: [])
        base.arguments = .init(game: [.text("--launchTarget"), .text("forgeclient")], jvm: [.text("-cp"), .text("${classpath}")])
        base.javaVersion = .init(majorVersion: 17, component: nil)
        base.generatedLibraries = [Artifact(path: "forge-patched.jar", url: nil)]
        let child = try installer.combinedProfile(instance: instance, base: base, installer: file, version: "HD_U_I6", sourceURL: URL(string: "https://example.test/optifine.jar")!)
        let manifest = try LoaderLaunchArguments.combining(base.merging(child: child), loaders: [.forge, .optifine])
        #expect(manifest.mainClass == main)
        #expect(manifest.arguments?.game?.flatMap { $0.values(architecture: "x86_64", features: [:]) } == ["--launchTarget", "forgeclient"])
        let library = try #require(manifest.libraries.first { $0.name.hasPrefix("optifine:OptiFine:") }), artifact = try #require(try library.artifact())
        let resources = try paths.resources(for: instance), normalized = try resources.libraryFile(artifact)
        let archive = try Archive(url: normalized, accessMode: .read)
        #expect(archive["META-INF/mods.toml"] == nil)
        #expect(archive["META-INF/services/cpw.mods.modlauncher.api.ITransformationService"] != nil)
        #expect(try InstanceTransfer.sha1(file) == originalHash)
        try OptiFineForgeSupport.prepareDiscoveryLibrary(manifest, resources: resources, protectExistingFiles: true)
        let client = try paths.clientJar("1.20.1", instance: instance)
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("client".utf8).write(to: client)
        try Data("forge processor output".utf8).write(to: paths.libraries.appendingPathComponent("forge-patched.jar"))
        let java = JavaRuntime(path: "/test/java", version: "17", major: 17, architecture: GameInstaller.architecture(for: manifest), vendor: "Test")
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        let cp = plan.arguments[try #require(plan.arguments.firstIndex(of: "-cp")) + 1]
        if main == "cpw.mods.modlauncher.Launcher" {
            #expect(!cp.contains(normalized.path))
            #expect(plan.arguments.contains(OptiFineForgeSupport.archiveProperty + normalized.path))
            #expect(cp.contains("transformer-discovery-1.0.jar"))
        } else { #expect(cp.contains(normalized.path)) }
        #expect(!plan.arguments.contains("--tweakClass"))
        try FileManager.default.removeItem(at: normalized)
        try await installer.repair(instance: instance, manifest: manifest) { _ in }
        #expect(try InstanceTransfer.sha1(normalized) == artifact.sha1)
        #expect(manifest.generatedLibraries?.first?.path == "forge-patched.jar")
    }

    @Test func missingModernServiceAndEarlyBootstrapBuildFailBeforeInstallation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = root.appendingPathComponent("legacy.jar"), early = root.appendingPathComponent("early.jar")
        try package(at: legacy, modern: false); try package(at: early, build: "20210923-190833")
        #expect(throws: (any Error).self) { try OptiFineForgeSupport.validatePackage(Archive(url: legacy, accessMode: .read), kind: .modLauncher) }
        #expect(throws: (any Error).self) { try OptiFineForgeSupport.validatePackage(Archive(url: early, accessMode: .read), kind: .bootstrap) }
    }

    @Test func knownBuildWarningsAreSeparateFromFamilyExclusions() throws {
        for version in ["14.23.5.2760", "14.23.5.2772", "1.12.2-14.23.5.2760"] {
            let pair: [LoaderSelection] = [.init(loader: .forge, version: version), .init(loader: .liteloader, version: "1.12.2-SNAPSHOT")]
            try LoaderCompatibility.validate(pair, game: "1.12.2")
            #expect(LoaderCompatibility.warnings(pair, game: "1.12.2").count == 1)
        }
        #expect(LoaderCompatibility.warnings([.init(loader: .forge, version: "14.23.5.2773"), .init(loader: .liteloader, version: "1.12.2")], game: "1.12.2").isEmpty)
        #expect(LoaderCompatibility.warnings([.init(loader: .forge, version: "28.2.2"), .init(loader: .optifine, version: "HD_U_F5")], game: "1.14.4").count == 1)
        #expect(LoaderCompatibility.warnings([.init(loader: .forge, version: "28.2.1"), .init(loader: .optifine, version: "HD_U_F5")], game: "1.14.4").isEmpty)
    }
}
