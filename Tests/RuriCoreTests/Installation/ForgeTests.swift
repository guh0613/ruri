import Testing
import Foundation
@testable import RuriCore

struct ForgeTests {
    @Test func neoForgeVersionFamilies() {
        #expect(ForgeCatalog.neoForgePrefix("1.20.2") == "20.2.")
        #expect(ForgeCatalog.neoForgePrefix("1.21") == "21.0.")
        #expect(ForgeCatalog.neoForgePrefix("1.21.1") == "21.1.")
        #expect(ForgeCatalog.neoForgePrefix("26.2") == "26.2.0.")
        #expect(ForgeCatalog.neoForgePrefix("26.1.2") == "26.1.2.")
        #expect(ForgeCatalog.neoForgePrefix("26.3-pre-3") == nil)
    }
    @Test func installerCoordinatesRespectLegacyNeoForge() throws {
        #expect(try ForgeCatalog.installerURL(loader: .forge, game: "1.21.1", version: "52.1.16").absoluteString == "https://maven.minecraftforge.net/net/minecraftforge/forge/1.21.1-52.1.16/forge-1.21.1-52.1.16-installer.jar")
        #expect(try ForgeCatalog.installerURL(loader: .neoforge, game: "1.20.1", version: "47.1.106").absoluteString.contains("net/neoforged/forge/1.20.1-47.1.106/forge-1.20.1-47.1.106"))
        #expect(try ForgeCatalog.installerURL(loader: .neoforge, game: "1.21.1", version: "21.1.250").absoluteString.contains("net/neoforged/neoforge/21.1.250/neoforge-21.1.250"))
    }
    @Test func generatedLibraryCanHaveEmptyDownloadURL() throws {
        let data = Data(#"{"path":"generated/client.jar","url":"","sha1":"586c071a3ead6c755c700ad6328f069006296196","size":28055793}"#.utf8)
        let artifact = try JSONDecoder().decode(Artifact.self, from: data)
        #expect(artifact.url == nil)
        #expect(artifact.sha1 != nil)
    }
    @Test func installerOutputSurvivesImmediateExit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = InstallerProcess()
        let executable = JavaRuntime(path: "/usr/bin/printf", version: "test", major: 1, architecture: "test", vendor: "test")
        let status = try await process.run(java: executable, arguments: ["final error\\n"], directory: directory, logURL: directory.appendingPathComponent("test.log")) { _ in }
        #expect(status == 0)
        #expect(await process.lastOutput() == "final error\n")
    }
    @Test func cancelledInstallerTerminatesPromptly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let process = InstallerProcess()
        let executable = JavaRuntime(path: "/bin/sleep", version: "test", major: 1, architecture: "test", vendor: "test")
        let task = Task { try await process.run(java: executable, arguments: ["30"], directory: directory, logURL: directory.appendingPathComponent("test.log")) { _ in } }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
