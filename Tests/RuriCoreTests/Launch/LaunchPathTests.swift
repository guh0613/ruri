import Foundation
import Testing
@testable import RuriCore

struct LaunchPathTests {
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
