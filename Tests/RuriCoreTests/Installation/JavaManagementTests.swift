import Foundation
import CryptoKit
import Testing
@testable import RuriCore

private enum JavaFixture {
    static let binary = Data("#!/bin/sh\nprintf '%s\\n' '    java.version = 21.0.7' '    os.arch = \(JavaRuntime.hostArchitecture)' '    java.vendor = Fixture'\n".utf8)
    static let library = Data("official library".utf8)
    static func hash(_ data: Data) -> String { Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static var manifest: Data {
        try! JSONSerialization.data(withJSONObject: ["files": [
            "jre.bundle/Contents/Home/bin/java": ["type": "file", "executable": true, "downloads": ["raw": ["url": "https://java.fixture.test/java", "sha1": hash(binary), "size": binary.count]]],
            "jre.bundle/Contents/Home/lib/support.bin": ["type": "file", "downloads": ["raw": ["url": "https://java.fixture.test/library", "sha1": hash(library), "size": library.count]]]
        ]], options: [.sortedKeys])
    }
}
private final class JavaFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "java.fixture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let data = url.path == "/manifest" ? JavaFixture.manifest : url.path == "/java" ? JavaFixture.binary : JavaFixture.library
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct JavaManagementTests {
    private func paths() throws -> LauncherPaths {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-java-management-\(UUID())")); try paths.prepare(); return paths
    }
    private func executable(_ data: Data = JavaFixture.binary, at file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file); try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }
    @Test func manualFoldersDeduplicateAliasesAndRelocationUpdatesReferences() async throws {
        let paths = try paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let bundle = paths.root.appendingPathComponent("First.jdk"), file = bundle.appendingPathComponent("Contents/Home/bin/java")
        try executable(at: file)
        _ = try await JavaRuntimeStore.add(bundle, paths: paths)
        let alias = paths.root.appendingPathComponent("Current Java")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: bundle.appendingPathComponent("Contents/Home"))
        let aliased = try await JavaRuntimeStore.add(alias, paths: paths)
        let old = alias.appendingPathComponent("bin/java").path
        #expect(aliased.settings.javaLocations?.count == 1)
        var instance = GameInstance(name: "Configured", gameVersion: "1.21.1"); instance.javaPath = old
        instance.launchOverrides = .init(); instance.launchOverrides?.java = .path(old)
        try StateStore.update(paths) { $0.instances = [instance]; $0.settings.defaultJava = .path(old) }
        let found = await JavaDiscovery.scan(paths: paths)
        #expect(found.contains { JavaDiscovery.sameExecutable($0.path, old) })
        let moved = paths.root.appendingPathComponent("Moved.jdk")
        try FileManager.default.moveItem(at: bundle, to: moved)
        let missing = try #require(await JavaDiscovery.inventory(paths: paths).first { $0.path == old })
        #expect(missing.runtime == nil && missing.issue != nil && missing.manual)
        let restored = try await JavaRuntimeStore.add(moved, replacing: old, paths: paths)
        let new = moved.appendingPathComponent("Contents/Home/bin/java").path
        #expect(restored.settings.defaultJava == .path(new))
        #expect(restored.instances[0].javaPath == new && restored.instances[0].launchOverrides?.java == .path(new))
        _ = try JavaRuntimeStore.forget(new, paths: paths)
        #expect(try StateStore.load(paths).settings.javaLocations?.isEmpty == true)
        #expect(FileManager.default.isExecutableFile(atPath: new))
    }
    @Test func repairReplacesBrokenFilesAndRespectsRuntimeLeases() async throws {
        let paths = try paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let runtime = RemoteJava(component: "java-runtime-delta", architecture: JavaRuntime.hostArchitecture, version: "21.0.7",
                                 manifest: .init(url: URL(string: "https://java.fixture.test/manifest"), sha1: JavaFixture.hash(JavaFixture.manifest), size: Int64(JavaFixture.manifest.count)))
        let directory = paths.runtimes.appendingPathComponent(runtime.id), binary = directory.appendingPathComponent("jre.bundle/Contents/Home/bin/java")
        try executable(Data("#!/bin/sh\nexit 1\n".utf8), at: binary)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [JavaFixtureProtocol.self]
        let downloader = DownloadManager(configuration: config, retryDelay: .zero), installer = JavaInstaller(paths: paths)
        do {
            let lease = try JavaRuntimeLease.shared(binary: binary, paths: paths)
            await #expect(throws: (any Error).self) { try await installer.install(runtime, downloader: downloader, repairing: true) { _ in } }
            #expect(throws: (any Error).self) { try JavaRuntimeStore.trash(runtime.id, paths: paths) }
            withExtendedLifetime(lease) {}
        }
        let repaired = try await installer.install(runtime, downloader: downloader, repairing: true) { _ in }
        #expect(repaired.major == 21 && repaired.architecture == runtime.architecture)
        #expect(try Data(contentsOf: directory.appendingPathComponent("jre.bundle/Contents/Home/lib/support.bin")) == JavaFixture.library)
        #expect(JavaRuntimeStore.descriptor(runtime.id, paths: paths)?.id == runtime.id)
        #expect(!FileManager.default.fileExists(atPath: paths.runtimes.appendingPathComponent(".partial-" + runtime.id).path))
    }
    @Test func removalRequiresExplicitReferenceResetAndPreservesOtherJava() throws {
        let paths = try paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let binary = paths.runtimes.appendingPathComponent("fixture/jre.bundle/Contents/Home/bin/java")
        try executable(at: binary)
        let external = paths.root.appendingPathComponent("External/bin/java"); try executable(at: external)
        var legacy = GameInstance(name: "Legacy", gameVersion: "1.21.1"); legacy.javaPath = binary.path
        var overridden = GameInstance(name: "Override", gameVersion: "1.21.1"); overridden.launchOverrides = .init(); overridden.launchOverrides?.java = .path(binary.path)
        try StateStore.update(paths) { $0.instances = [legacy, overridden]; $0.settings.defaultJava = .path(binary.path) }
        #expect(try JavaRuntimeStore.references(to: "fixture", paths: paths).count == 3)
        #expect(throws: (any Error).self) { try JavaRuntimeStore.trash("fixture", paths: paths) }
        let result = try JavaRuntimeStore.trash("fixture", paths: paths, resetReferences: true)
        defer { if let url = result.trashedURL { try? FileManager.default.removeItem(at: url) } }
        #expect(result.state.settings.defaultJava == .automatic && result.state.instances[0].javaPath == nil)
        #expect(result.state.instances[1].launchOverrides?.java == .automatic)
        #expect(FileManager.default.isExecutableFile(atPath: external.path))
    }
    @Test func unresponsiveJavaProbeTimesOut() throws {
        let paths = try paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let binary = paths.root.appendingPathComponent("bin/java")
        try executable(Data("#!/bin/sh\nexec /bin/sleep 10\n".utf8), at: binary)
        #expect(throws: (any Error).self) { try ProcessRunner.run(binary, arguments: [], timeout: 0.05) }
    }
}
