import Foundation
import CryptoKit
import Testing
import ZIPFoundation
@testable import RuriCore

private enum MRFixture {
    static let data = Data("known mod file".utf8)
    static let sha1 = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    static let sha512 = SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
    static let download = URL(string: "https://cdn.modrinth.com/data/project/versions/version/known.jar")!
    static func version(hash: String = sha512) -> [String: Any] {
        ["id": "version", "project_id": "project", "name": "Known Mod", "version_number": "1.0", "game_versions": ["1.21.1"], "loaders": ["fabric"], "dependencies": [],
         "files": [["url": download.absoluteString, "filename": "known.jar", "primary": true, "size": data.count, "hashes": ["sha1": sha1, "sha512": hash]]]]
    }
}
private final class MRProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let data: Data; let status: Int
        if url.host == "api.modrinth.com", url.path == "/v2/version_files", request.httpMethod == "POST" {
            let hash = request.value(forHTTPHeaderField: "Ruri-Bad-Fixture") == "true" ? String(repeating: "0", count: 128) : MRFixture.sha512
            data = try! JSONSerialization.data(withJSONObject: [MRFixture.sha512: MRFixture.version(hash: hash)]); status = 200
        } else if url == MRFixture.download { data = MRFixture.data; status = 200 }
        else { data = Data(); status = 404 }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(data.count)])!, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct MRPackTests {
    func setup() throws -> (LauncherPaths, URL) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        let source = paths.cache.appendingPathComponent("source"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return (paths, source)
    }
    func config() -> URLSessionConfiguration { let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MRProtocol.self]; return config }
    func file(_ path: String, client: String = "required", downloads: [URL] = [MRFixture.download]) -> ModpackIndex.File {
        .init(path: path, hashes: ["sha1": MRFixture.sha1, "sha512": MRFixture.sha512], env: ["client": client], downloads: downloads, fileSize: Int64(MRFixture.data.count))
    }
    func index(_ files: [ModpackIndex.File], at root: URL) throws {
        let index = ModpackIndex(formatVersion: 1, game: "minecraft", name: "Test Pack", versionId: "v2", dependencies: ["minecraft": "1.21.1", "fabric-loader": "0.19.5"], files: files)
        try JSONEncoder().encode(index).write(to: root.appendingPathComponent("modrinth.index.json"))
    }
    func write(_ data: Data, _ path: String, in root: URL) throws {
        let target = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: target)
    }
    @Test func clientOverridesWinAndOptionalFilesCanBeSkipped() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try index([file("mods/required.jar"), file("mods/optional.jar", client: "optional"), file("mods/server.jar", client: "unsupported", downloads: []), file("config/overridden.json")], at: source)
        try write(Data("common".utf8), "overrides/config/overridden.json", in: source)
        try write(Data("client".utf8), "client-overrides/config/overridden.json", in: source)
        try write(Data("server".utf8), "server-overrides/config/server.json", in: source)
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        #expect(preview.format == "Modrinth"); #expect(preview.instance.loader == .fabric)
        #expect(preview.packFiles.map(\.path) == ["mods/required.jar", "mods/optional.jar"])
        #expect(preview.optionalFiles.map(\.id) == ["mods/optional.jar"])
        #expect(try Data(contentsOf: preview.game.appendingPathComponent("config/overridden.json")) == Data("client".utf8))
        let chosen = preview.selectingOptionalFiles(excluding: ["mods/optional.jar", "mods/required.jar"])
        #expect(chosen.selectedPackFiles.map(\.path) == ["mods/required.jar"])
        // A previous failed attempt may already have downloaded optional content.
        try write(MRFixture.data, "mods/optional.jar", in: preview.game)
        try await transfer.completeFiles(chosen, downloader: DownloadManager(configuration: config(), retryDelay: .zero)) { _ in }
        let installed = try await transfer.install(chosen, name: "Installed") { $0 }
        #expect(try Data(contentsOf: paths.game(installed.id).appendingPathComponent("mods/required.jar")) == MRFixture.data)
        #expect(!FileManager.default.fileExists(atPath: paths.game(installed.id).appendingPathComponent("mods/optional.jar").path))
        #expect(!FileManager.default.fileExists(atPath: paths.game(installed.id).appendingPathComponent("config/server.json").path))
        #expect(try Data(contentsOf: source.appendingPathComponent("overrides/config/overridden.json")) == Data("common".utf8))
        await transfer.discard(preview)
    }
    @Test func downloadFallsBackToNextDeclaredURL() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try index([file("mods/required.jar", downloads: [URL(string: "https://unavailable.ruri.test/file.jar")!, MRFixture.download])], at: source)
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        let manager = DownloadManager(configuration: config(), retryDelay: .zero)
        try await transfer.completeFiles(preview, downloader: manager) { _ in }
        #expect(try Data(contentsOf: preview.game.appendingPathComponent("mods/required.jar")) == MRFixture.data)
        #expect(await manager.transfers().contains { $0.host == "cdn.modrinth.com" && $0.state == .completed })
        await transfer.discard(preview)
    }
    @Test func exportReferencesExactFilesAndKeepsLocalAndDisabledContent() async throws {
        let (paths, _) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Round trip", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.19.5")
        let game = paths.game(instance.id)
        for (path, data) in [("mods/known.jar", MRFixture.data), ("mods/local.jar", Data("local".utf8)), ("mods/disabled.jar.disabled", MRFixture.data), ("config/empty.json", Data())] { try write(data, path, in: game) }
        try write(Data("regenerable".utf8), ".fabric/remappedJars/client.jar", in: game)
        try write(Data("private diagnostic".utf8), "hs_err_pid42.log", in: game)
        try write(Data("launcher credential".utf8), "launcher_msa_credentials.bin", in: game)
        let session = URLSession(configuration: config()); defer { session.invalidateAndCancel() }
        let transfer = InstanceTransfer(paths: paths); let destination = paths.cache.appendingPathComponent("test.mrpack")
        try await transfer.exportMRPack(instance, game: game, to: destination, includeWorlds: true, details: .init(version: "3.0", description: "Fixture"), service: ModrinthService(client: HTTPClient(session: session))) { _ in }
        let archive = try Archive(url: destination, accessMode: .read)
        #expect(archive["client-overrides/.fabric/remappedJars/client.jar"] == nil)
        #expect(archive["client-overrides/hs_err_pid42.log"] == nil)
        #expect(archive["client-overrides/launcher_msa_credentials.bin"] == nil)
        #expect(archive["modrinth.index.json"] != nil); #expect(archive["client-overrides/mods/known.jar"] == nil)
        #expect(archive["client-overrides/mods/local.jar"] != nil); #expect(archive["client-overrides/mods/disabled.jar.disabled"] != nil)
        let preview = try await transfer.prepare(destination)
        #expect(preview.packFiles.count == 1); #expect(preview.packFiles.first?.sha512 == MRFixture.sha512)
        try await transfer.completeFiles(preview, downloader: DownloadManager(configuration: config(), retryDelay: .zero)) { _ in }
        let imported = try await transfer.install(preview, name: "Imported") { $0 }
        for path in ["mods/known.jar", "mods/local.jar", "mods/disabled.jar.disabled", "config/empty.json"] {
            #expect(try Data(contentsOf: paths.game(imported.id).appendingPathComponent(path)) == Data(contentsOf: game.appendingPathComponent(path)))
        }
        await transfer.discard(preview)
    }
    @Test func bothHashesAndPortablePathsAreRequired() async throws {
        for value in [file("../escape"), file("C:/outside.jar"), ModpackIndex.File(path: "mods/missing.jar", hashes: ["sha1": MRFixture.sha1], env: nil, downloads: [MRFixture.download], fileSize: 1)] {
            let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
            try index([value], at: source)
            await #expect(throws: (any Error).self) { try await InstanceTransfer(paths: paths).prepare(source) }
        }
    }
    @Test func hashLookupRejectsMismatchedVersionResponses() async throws {
        let config = config(); config.httpAdditionalHeaders = ["Ruri-Bad-Fixture": "true"]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) { try await ModrinthService(client: HTTPClient(session: session)).versionsFromHashes([MRFixture.sha512]) }
    }
}
