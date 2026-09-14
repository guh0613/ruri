import Foundation
import Testing
@testable import RuriCore

struct GameJavaRequirementTests {
    private func manifest(major: Int = 17) -> VersionManifest {
        VersionManifest(id: "1.20.1", mainClass: "net.minecraft.client.main.Main", libraries: [], javaVersion: .init(majorVersion: major, component: nil))
    }
    private func runtime(_ major: Int, version: String? = nil, architecture: String? = nil) -> JavaRuntime {
        .init(path: "/java-\(major)-\(version ?? "")-\(architecture ?? "")", version: version ?? String(major), major: major,
              architecture: architecture ?? GameInstaller.architecture(for: manifest()), vendor: "Test")
    }

    @Test func reusesNewerJavaWhenRecommendedVersionIsAbsent() throws {
        let requirement = try GameJavaRequirement(instance: GameInstance(name: "Vanilla", gameVersion: "1.20.1"), manifest: manifest())
        #expect(try requirement.select(from: [runtime(8), runtime(21)])?.major == 21)
        #expect(try requirement.select(from: [runtime(21), runtime(17)])?.major == 17)
        #expect(try requirement.select(from: [runtime(17, version: "17.0.2"), runtime(17, version: "17.0.10")])?.version == "17.0.10")
        #expect(try requirement.select(from: [runtime(8)]) == nil)
    }

    @Test func exactMajorAndPackRestrictionsRemainAuthoritative() throws {
        var instance = GameInstance(name: "Pack", gameVersion: "1.20.1")
        instance.supportedJavaMajors = [17, 21]
        #expect(try GameJavaRequirement(instance: instance, manifest: manifest()).select(from: [runtime(25), runtime(21)])?.major == 21)
        instance.javaMajor = 17
        #expect(try GameJavaRequirement(instance: instance, manifest: manifest()).select(from: [runtime(21)]) == nil)
        instance.javaMajor = 25
        #expect(throws: (any Error).self) { try GameJavaRequirement(instance: instance, manifest: manifest()) }
        instance.javaMajor = nil; instance.supportedJavaMajors = [8]
        #expect(throws: (any Error).self) { try GameJavaRequirement(instance: instance, manifest: manifest()) }
    }

    @Test func explicitPathsAreNotSilentlyReplaced() throws {
        var instance = GameInstance(name: "Path", gameVersion: "1.20.1")
        instance.javaPath = runtime(21).path
        let requirement = try GameJavaRequirement(instance: instance, manifest: manifest())
        #expect(try requirement.select(from: [runtime(17), runtime(21)])?.major == 21)
        #expect(throws: (any Error).self) { try requirement.select(from: [runtime(17)]) }
        instance.javaPath = runtime(8).path
        #expect(throws: (any Error).self) { try GameJavaRequirement(instance: instance, manifest: manifest()).select(from: [runtime(8), runtime(21)]) }
    }

    @Test func gameArchitectureAndLegacyLaunchWrapperAreRespected() throws {
        let requirement = try GameJavaRequirement(instance: GameInstance(name: "Native", gameVersion: "1.20.1"), manifest: manifest())
        let wrong = requirement.architecture == "aarch64" ? "x86_64" : "aarch64"
        #expect(try requirement.select(from: [runtime(21, architecture: wrong)]) == nil)
        var legacy = manifest(major: 8)
        legacy.mainClass = "net.minecraft.launchwrapper.Launch"
        legacy.libraries = [.init(name: "net.minecraft:launchwrapper:1.12", downloads: nil, rules: nil, natives: nil, extract: nil)]
        let legacyRequirement = try GameJavaRequirement(instance: GameInstance(name: "Old Forge", gameVersion: "1.12.2"), manifest: legacy)
        #expect(try legacyRequirement.select(from: [runtime(21, architecture: legacyRequirement.architecture)]) == nil)
        #expect(try legacyRequirement.select(from: [runtime(8, architecture: legacyRequirement.architecture)])?.major == 8)
    }

    @Test func installationToolsCanReuseNewerNativeJava() {
        let java = runtime(21, architecture: JavaRuntime.hostArchitecture)
        #expect(JavaDiscovery.selectForInstallation(from: [java], minimumMajor: 8) == java)
        #expect(JavaDiscovery.selectForInstallation(from: [java], minimumMajor: 25) == nil)
    }
}
