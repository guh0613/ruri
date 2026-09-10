import Foundation
import Testing
@testable import RuriCore

struct LaunchPathTests {
    @Test(arguments: [true, false])
    func sharedArtifactsAppearOnceWithoutDroppingNativeMetadata(explicitClasspath: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-forge classpath-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        try paths.prepare()
        let instance = GameInstance(name: "Forge", gameVersion: "1.18.2", loader: .forge)
        var state = PersistentState(); state.instances = [instance]; try StateStore.save(state, to: paths)
        var manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"""
        {"id":"fixture","mainClass":"cpw.mods.bootstraplauncher.BootstrapLauncher","javaVersion":{"majorVersion":17},
         "libraries":[
           {"name":"ca.weblite:java-objc-bridge:1.0.0",
            "downloads":{"artifact":{"path":"bridge.jar"},"classifiers":{"natives-osx":{"path":"bridge-natives.jar"}}},
            "natives":{"osx":"natives-osx"},"rules":[{"action":"allow","os":{"name":"osx"}}]},
           {"name":"fixture:middle:1","downloads":{"artifact":{"path":"middle.jar"}}},
           {"name":"ca.weblite:java-objc-bridge:1.0.0","downloads":{"artifact":{"path":"bridge.jar"}},
            "rules":[{"action":"allow","os":{"name":"osx"}}]},
           {"name":"fixture:alias:1","downloads":{"artifact":{"repositoryPath":"libraries/bridge.jar"}}},
           {"name":"fixture:middle:1:extra","downloads":{"artifact":{"path":"extra.jar"}}},
           {"name":"fixture:windows:1","rules":[{"action":"allow","os":{"name":"windows"}}]}
         ],"arguments":{"jvm":["-cp","${classpath}"],"game":[]}}
        """#.utf8))
        if !explicitClasspath { manifest.arguments = nil }
        // Both declarations survive library selection because one carries
        // native extraction metadata required by this Forge-era manifest.
        let resolution = MinecraftManifestResolution(manifest: manifest, clientFile: paths.versions.appendingPathComponent("1.18.2/1.18.2.jar"),
            libraries: manifest.libraries.map { .init(library: $0, localFile: nil, sourceMetadata: nil) }, warnings: [], sourceManifests: [])
        manifest = try resolution.selectingLibraries().manifest
        #expect(manifest.libraries.filter { $0.name == "ca.weblite:java-objc-bridge:1.0.0" }.count == 2)
        #expect(try manifest.libraries.first?.nativeArtifact(architecture: "x86_64")?.path == "bridge-natives.jar")
        let expected = ["bridge.jar", "middle.jar", "extra.jar"].map { paths.libraries.appendingPathComponent($0) }
            + [paths.versions.appendingPathComponent("1.18.2/1.18.2.jar")]
        for file in expected {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture jar".utf8).write(to: file)
        }
        let java = JavaRuntime(path: "/test/java", version: "17", major: 17, architecture: GameInstaller.architecture(for: manifest), vendor: "Test")
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        let index = try #require(plan.arguments.firstIndex(of: "-cp"))
        #expect(plan.arguments[index + 1].split(separator: ":").map(String.init) == expected.map { $0.resolvingSymlinksInPath().path })
    }

    @Test func bootstrapClasspathAndModulePathAgreeWhenLibrariesUseASymbolicLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-library alias-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root.appendingPathComponent("data"))
        let storage = root.appendingPathComponent("shared libraries")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: paths.libraries, withDestinationURL: storage)
        try paths.prepare()
        let instance = GameInstance(name: "Bootstrap", gameVersion: "1.21.1", loader: .neoforge)
        var state = PersistentState(); state.instances = [instance]; try StateStore.save(state, to: paths)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"""
        {"id":"fixture","mainClass":"cpw.mods.bootstraplauncher.BootstrapLauncher","javaVersion":{"majorVersion":21},
         "libraries":[{"name":"cpw.mods:bootstraplauncher:2.0.2"}],
         "arguments":{"game":[],"jvm":["-cp","${classpath}","-p","${library_directory}/cpw/mods/bootstraplauncher/2.0.2/bootstraplauncher-2.0.2.jar","-DlibraryDirectory=${library_directory}"]}}
        """#.utf8))
        let relative = try Library.mavenPath("cpw.mods:bootstraplauncher:2.0.2")
        for file in [storage.appendingPathComponent(relative), paths.versions.appendingPathComponent("1.21.1/1.21.1.jar")] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture jar".utf8).write(to: file)
        }
        let java = JavaRuntime(path: "/test/java", version: "21", major: 21, architecture: GameInstaller.architecture(for: manifest), vendor: "Test")
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        let moduleIndex = try #require(plan.arguments.firstIndex(of: "-p"))
        let classIndex = try #require(plan.arguments.firstIndex(of: "-cp"))
        let modules = plan.arguments[moduleIndex + 1].split(separator: ":")
        let classes = plan.arguments[classIndex + 1].split(separator: ":")
        #expect(modules.count == 1 && classes.contains(modules[0]))
        #expect(String(modules[0]) == storage.appendingPathComponent(relative).resolvingSymlinksInPath().path)
        #expect(plan.arguments.contains("-DlibraryDirectory=\(storage.resolvingSymlinksInPath().path)"))
    }
}
