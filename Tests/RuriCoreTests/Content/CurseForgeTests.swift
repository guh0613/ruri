import Foundation
import CryptoKit
import Testing
@testable import RuriCore

private final class CFTestServer: @unchecked Sendable {
    let lock = NSLock()
    let responses: [String: Data]
    var requests: [URLRequest] = []
    init(_ responses: [String: Data]) { self.responses = responses }
    func receive(_ request: URLRequest) -> Data? { lock.withLock { requests.append(request); return responses[request.url!.path] } }
    var received: [URLRequest] { lock.withLock { requests } }
}
private final class CFTestRegistry: @unchecked Sendable {
    let lock = NSLock(); var values: [String: CFTestServer] = [:]
    func set(_ server: CFTestServer?, id: String) { lock.withLock { values[id] = server } }
    func get(_ id: String) -> CFTestServer? { lock.withLock { values[id] } }
}
private final class CFTestProtocol: URLProtocol, @unchecked Sendable {
    static let servers = CFTestRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let id = request.value(forHTTPHeaderField: "Ruri-Test-ID") ?? ""
        guard let data = Self.servers.get(id)?.receive(request) else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct CurseForgeTests {
    let body = Data("test-jar-contents".utf8)
    func project(_ id: Int, allowed: Bool = true, kind: Int = 6) -> [String: Any] {
        ["id": id, "gameId": 432, "name": "Project \(id)", "slug": "project-\(id)", "summary": "Fixture", "downloadCount": 25, "classId": kind,
         "authors": [["name": "Author"]], "allowModDistribution": allowed, "links": ["websiteUrl": "https://www.curseforge.com/minecraft/mc-mods/project-\(id)"]]
    }
    func file(_ id: Int, project: Int, dependencies: [[String: Int]] = [], md5Only: Bool = false, release: Int = 1, date: String = "2026-09-01T12:00:00Z") -> [String: Any] {
        let hash = md5Only ? Insecure.MD5.hash(data: body).map { String(format: "%02x", $0) }.joined() : Insecure.SHA1.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return ["id": id, "modId": project, "displayName": "Version \(id)", "fileName": "mod-\(id).jar", "fileDate": date, "fileLength": body.count,
                "releaseType": release, "downloadUrl": "https://download.cf.test/mod-\(id).jar", "gameVersions": ["1.21.1", "Fabric"], "dependencies": dependencies,
                "hashes": [["algo": md5Only ? 2 : 1, "value": hash]], "isAvailable": true]
    }
    func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func decoded(_ value: [String: Any]) throws -> CurseForgeFile { try JSONDecoder().decode(CurseForgeFile.self, from: json(value)) }
    private func service(_ responses: [String: Data]) -> (CurseForgeService, CFTestServer, String, URLSession) {
        let id = UUID().uuidString; let server = CFTestServer(responses); CFTestProtocol.servers.set(server, id: id)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CFTestProtocol.self]; config.httpAdditionalHeaders = ["Ruri-Test-ID": id]
        let session = URLSession(configuration: config)
        return (CurseForgeService(apiKey: "test-key", client: HTTPClient(session: session)), server, id, session)
    }
    @Test func searchAndVersionQueriesUseOfficialIdentifiers() async throws {
        let (service, server, id, session) = service([
            "/v1/mods/search": try json(["data": [project(7)], "pagination": ["index": 20, "pageSize": 20, "resultCount": 1, "totalCount": 21]]),
            "/v1/mods/7/files": try json(["data": [file(70, project: 7)]])
        ])
        defer { CFTestProtocol.servers.set(nil, id: id); session.invalidateAndCancel() }
        let result = try await service.search("fabric 中文", type: "mod", offset: 20)
        #expect(result.data.first?.id == 7); #expect(result.pagination?.totalCount == 21)
        _ = try await service.files(project: 7, game: "1.21.1", loader: .neoforge)
        let requests = server.received
        #expect(requests.allSatisfy { $0.url?.host == "api.curseforge.com" && $0.value(forHTTPHeaderField: "x-api-key") == "test-key" })
        let search = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(search.contains(.init(name: "gameId", value: "432"))); #expect(search.contains(.init(name: "classId", value: "6")))
        #expect(search.contains(.init(name: "searchFilter", value: "fabric 中文")))
        #expect(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!.contains(.init(name: "modLoaderType", value: "6")))
    }
    @Test func searchAndDetailAcceptEmptyOptionalLinks() async throws {
        var entry = project(7)
        entry["links"] = ["websiteUrl": "https://www.curseforge.com/minecraft/mc-mods/project-7", "wikiUrl": "", "issuesUrl": "", "sourceUrl": NSNull()]
        let (service, _, id, session) = service([
            "/v1/mods/search": try json(["data": [entry, project(8)]]),
            "/v1/mods/7": try json(["data": entry])
        ])
        defer { CFTestProtocol.servers.set(nil, id: id); session.invalidateAndCancel() }
        let page = try await service.search("", type: "mod")
        #expect(page.data.map(\.id) == [7, 8])
        for item in [try #require(page.data.first), try await service.project(7)] {
            #expect(item.links?.websiteUrl?.absoluteString == "https://www.curseforge.com/minecraft/mc-mods/project-7")
            #expect(item.links?.wikiUrl == nil)
            #expect(item.links?.issuesUrl == nil)
            #expect(item.links?.sourceUrl == nil)
        }
    }
    @Test func optionalWebURLsHandleMissingNullEmptyAndInvalidValues() throws {
        for value in [nil, NSNull(), "", " \n\t ", "https://[", "/relative/path", "file:///tmp/wiki", "javascript:alert(1)", "https://user:secret@example.test/wiki"] as [Any?] {
            var links: [String: Any] = [:], logo: [String: Any] = [:]
            if let value {
                links = Dictionary(uniqueKeysWithValues: ["websiteUrl", "wikiUrl", "issuesUrl", "sourceUrl"].map { ($0, value) })
                logo = ["thumbnailUrl": value]
            }
            var entry = project(7); entry["links"] = links; entry["logo"] = logo
            let result = try JSONDecoder().decode(CurseForgeProject.self, from: json(entry))
            #expect(result.links?.websiteUrl == nil)
            #expect(result.links?.wikiUrl == nil)
            #expect(result.links?.issuesUrl == nil)
            #expect(result.links?.sourceUrl == nil)
            #expect(result.logo?.thumbnailUrl == nil)
            #expect(result.page(for: 70).absoluteString == "https://www.curseforge.com/minecraft/mc-mods/project-7/files/70")
        }
    }
    @Test func validOptionalWebURLsArePreservedAndSchemaErrorsStillFail() throws {
        var entry = project(7)
        entry["links"] = ["websiteUrl": "https://www.curseforge.com/minecraft/mc-mods/project-7", "wikiUrl": " http://example.test/wiki \n",
                          "issuesUrl": "https://example.test/issues?q=bug#new", "sourceUrl": "https://example.test/source"]
        entry["logo"] = ["thumbnailUrl": "https://media.forgecdn.net/test.png"]
        let result = try JSONDecoder().decode(CurseForgeProject.self, from: json(entry))
        #expect(result.links?.wikiUrl?.absoluteString == "http://example.test/wiki")
        #expect(result.links?.issuesUrl?.absoluteString == "https://example.test/issues?q=bug#new")
        #expect(result.links?.sourceUrl?.absoluteString == "https://example.test/source")
        #expect(result.logo?.thumbnailUrl?.absoluteString == "https://media.forgecdn.net/test.png")
        entry["links"] = ["wikiUrl": 42]
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CurseForgeProject.self, from: json(entry)) }
        entry["links"] = [:] as [String: Any]
        entry["id"] = nil
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CurseForgeProject.self, from: json(entry)) }
    }
    @Test func requiredDependenciesAndDistributionRestrictionsArePlanned() async throws {
        let root = file(10, project: 1, dependencies: [["modId": 2, "relationType": 3], ["modId": 3, "relationType": 2]])
        let dependency = file(20, project: 2, dependencies: [["modId": 1, "relationType": 3]])
        let (service, server, id, session) = service([
            "/v1/mods/1": try json(["data": project(1)]), "/v1/mods/2": try json(["data": project(2, allowed: false)]),
            "/v1/mods/2/files": try json(["data": [dependency]])
        ])
        defer { CFTestProtocol.servers.set(nil, id: id); session.invalidateAndCancel() }
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Test", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.19.5")
        let plan = try await service.plan(file: decoded(root), instance: instance, paths: paths)
        #expect(plan.files.map(\.id) == [10, 20]); #expect(plan.manualFiles.map(\.id) == [20])
        #expect(plan.files[0].record.requiredProjects == ["2"])
        #expect(plan.manualFiles[0].downloadURL == nil)
        #expect(plan.manualFiles[0].pageURL.absoluteString == "https://www.curseforge.com/minecraft/mc-mods/project-2/files/20")
        #expect(!server.received.contains { $0.url!.path.contains("/3") || $0.url!.path == "/v1/mods/1/files" })
    }
    @Test func manualFilesAreVerifiedBeforeContentChanges() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let project = try JSONDecoder().decode(CurseForgeProject.self, from: json(project(1, allowed: false)))
        let file = try decoded(file(10, project: 1, md5Only: true))
        let instance = GameInstance(name: "Test", gameVersion: "1.21.1", loader: .fabric)
        let plan = CurseForgeContentPlan(instance: instance, title: project.name, files: [.init(project: project, file: file, kind: .mod)])
        let local = paths.cache.appendingPathComponent(file.fileName); try Data("wrong".utf8).write(to: local)
        let service = CurseForgeService(apiKey: "")
        await #expect(throws: (any Error).self) { try await service.install(plan, paths: paths, downloader: DownloadManager(), manualFiles: [10: local]) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: paths.game(instance.id).path))
        try body.write(to: local)
        try await service.install(plan, paths: paths, downloader: DownloadManager(), manualFiles: [10: local]) { _ in }
        #expect(try Data(contentsOf: paths.game(instance.id).appendingPathComponent("mods/mod-10.jar")) == body)
        let records = try await ContentManager(paths: paths, instanceID: instance.id).records()
        #expect(records.first?.provider == "curseforge"); #expect(records.first?.md5 == file.md5)
    }
    @Test func bulkPackResolutionValidatesProjectFilePairing() async throws {
        let (service, server, id, session) = service(["/v1/mods": try json(["data": [project(1)]]), "/v1/mods/files": try json(["data": [file(10, project: 1)]])])
        defer { CFTestProtocol.servers.set(nil, id: id); session.invalidateAndCancel() }
        let resolved = try await service.resolve([.init(projectID: 1, fileID: 10)])
        #expect(resolved.first?.file.id == 10)
        #expect(server.received.allSatisfy { $0.httpMethod == "POST" })
        await #expect(throws: (any Error).self) { try await service.resolve([.init(projectID: 99, fileID: 10)]) }
    }
    @Test func emptyKeyAndUnavailableFileFailClearly() async throws {
        let (unused, server, id, session) = service([:]); _ = unused
        defer { CFTestProtocol.servers.set(nil, id: id); session.invalidateAndCancel() }
        let service = CurseForgeService(apiKey: "", client: HTTPClient(session: session))
        await #expect(throws: (any Error).self) { try await service.search("test", type: "mod") }
        #expect(server.received.isEmpty)
        var record = file(10, project: 1); record["hashes"] = []
        let invalid = try decoded(record)
        #expect(throws: (any Error).self) { try invalid.downloadItem(to: URL(fileURLWithPath: "/tmp/test"), permittedURL: invalid.downloadURL) }
    }
    @Test func providerNamespacesKeepUnrelatedDependenciesIndependent() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let id = UUID(); let manager = ContentManager(paths: paths, instanceID: id)
        let source = paths.cache.appendingPathComponent("data.jar"); try body.write(to: source)
        let hash = Insecure.SHA1.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let modrinth = ManagedContent(projectID: "123", versionID: "a", title: "Unrelated", versionName: "1", kind: .mod, filename: "unrelated.jar", sha1: hash, size: Int64(body.count))
        let dependent = ManagedContent(provider: "curseforge", projectID: "456", versionID: "b", title: "Dependent", versionName: "1", kind: .mod, filename: "dependent.jar", sha1: hash, size: Int64(body.count), requiredProjects: ["123"])
        try await manager.install([.init(record: modrinth, source: source)])
        await #expect(throws: (any Error).self) { try await manager.install([.init(record: dependent, source: source)]) }
        #expect(try await manager.records().count == 1)
    }
    @Test func updatesUseCompatibleStableVersionsWithoutDowngrading() async throws {
        let (service, server, id, session) = service([
            "/v1/mods/1/files": try json(["data": [file(12, project: 1, release: 2, date: "2026-09-09T12:00:00Z"), file(11, project: 1)]]),
            "/v1/mods/2/files": try json(["data": [file(21, project: 2, date: "2026-08-01T12:00:00Z")]])
        ])
        defer { CFTestProtocol.servers.set(nil, id: id); session.invalidateAndCancel() }
        let first = ManagedContent(provider: "curseforge", projectID: "1", versionID: "10", title: "Project 1", versionName: "old", publishedAt: "2026-08-01T12:00:00Z", kind: .mod, filename: "old.jar", size: 1)
        let second = ManagedContent(provider: "curseforge", projectID: "2", versionID: "20", title: "Project 2", versionName: "newer", publishedAt: "2026-09-02T12:00:00Z", kind: .mod, filename: "newer.jar", size: 1)
        let unrelated = ManagedContent(projectID: "unrelated", versionID: "v", title: "Modrinth", versionName: "v", kind: .mod, filename: "mr.jar", size: 1)
        let result = try await service.updates(for: [first, second, unrelated], instance: GameInstance(name: "Test", gameVersion: "1.21.1", loader: .fabric))
        #expect(result.count == 1); #expect(result.first?.available.id == 11)
        #expect(server.received.count == 2)
    }
}
