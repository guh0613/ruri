import Foundation
import CryptoKit
import Testing
@testable import RuriCore

struct ContentIdentificationTests {
    private func file(_ paths: LauncherPaths, id: UUID, name: String = "renamed.jar.disabled", data: Data = Data("hello".utf8)) throws -> LocalContentFile {
        let url = paths.game(id).appendingPathComponent("mods/" + name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        let enabled = !name.hasSuffix(".disabled")
        return LocalContentFile(url: url, filename: enabled ? name : String(name.dropLast(9)), title: "Local", version: nil, modID: nil, kind: .mod, enabled: enabled, size: Int64(data.count), managed: nil)
    }
    private func responses(_ digest: ContentFileDigest, collision: Bool = false) throws -> [String: Data] {
        let cf = CurseForgeTests()
        var curseFile = cf.file(70, project: 7)
        curseFile["fileFingerprint"] = digest.fingerprint
        curseFile["fileLength"] = digest.size
        curseFile["hashes"] = [["algo": 1, "value": collision ? String(repeating: "0", count: 40) : digest.sha1]]
        let version: [String: Any] = ["id": "v1", "project_id": "project", "name": "Known Mod", "version_number": "1.0", "date_published": "2025-01-01T00:00:00Z", "game_versions": ["1.21.1"], "loaders": ["fabric"], "dependencies": [],
            "files": [["url": "https://cdn.modrinth.com/known.jar", "filename": "original.jar", "primary": true, "size": digest.size, "hashes": ["sha1": digest.sha1, "sha512": digest.sha512]]]]
        return [
            "api.modrinth.com/v2/version_files": try cf.json([digest.sha512: version]),
            "api.modrinth.com/v2/projects": try cf.json([["id": "project", "slug": "known", "title": "Known Mod", "description": "Remote description", "project_type": "mod", "downloads": 0, "categories": [], "versions": []]]),
            "api.curseforge.com/v1/fingerprints/432": try cf.json(["data": ["exactMatches": [["file": curseFile]], "partialMatches": []]]),
            "api.curseforge.com/v1/mods": try cf.json(["data": [cf.project(7)]])
        ]
    }
    @Test func bothPlatformsIdentifyRenamedDisabledFilesAndReuseDiskCache() async throws {
        let (paths, id, manager) = try ContentManagerTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let local = try file(paths, id: id), digest = try ContentFileDigest.read(local.url)
        let server = EndpointHTTPFixture(try responses(digest)); defer { server.close() }
        let client = HTTPClient(session: server.session)
        let service = ContentIdentificationService(cacheDirectory: paths.cache, modrinth: ModrinthService(client: client), curseforge: CurseForgeService(apiKey: "fixture", client: client))
        let result = try await service.identify([local])
        #expect(result.failures.isEmpty)
        #expect(Set(result.matches[local.id]?.map { $0.record.provider } ?? []) == ["modrinth", "curseforge"])
        #expect(try await manager.records().isEmpty)
        let initialRequests = server.requests.count
        let fingerprint = try #require(server.requests.first { $0.url.path == "/v1/fingerprints/432" })
        let body = try JSONDecoder().decode([String: [UInt32]].self, from: fingerprint.body)
        #expect(body["fingerprints"] == [digest.fingerprint])
        let cached = ContentIdentificationService(cacheDirectory: paths.cache, modrinth: ModrinthService(client: client), curseforge: CurseForgeService(apiKey: "fixture", client: client))
        _ = try await cached.identify([local])
        #expect(server.requests.count == initialRequests)
        _ = try await cached.identify([local], refresh: true)
        #expect(server.requests.count > initialRequests)
    }
    @Test func failedProviderDoesNotHideOtherMatchAndFingerprintCollisionIsRejected() async throws {
        let (paths, id, _) = try ContentManagerTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let local = try file(paths, id: id), digest = try ContentFileDigest.read(local.url)
        var responses = try responses(digest)
        responses["api.modrinth.com/v2/version_files"] = nil
        let server = EndpointHTTPFixture(responses); defer { server.close() }
        let client = HTTPClient(session: server.session)
        let service = ContentIdentificationService(cacheDirectory: paths.cache, modrinth: ModrinthService(client: client), curseforge: CurseForgeService(apiKey: "fixture", client: client))
        let result = try await service.identify([local])
        #expect(result.failures.count == 1 && result.matches[local.id]?.first?.record.provider == "curseforge")
        let collisionServer = EndpointHTTPFixture(try self.responses(digest, collision: true)); defer { collisionServer.close() }
        let collisionClient = HTTPClient(session: collisionServer.session)
        let collisionResult = try await ContentIdentificationService(cacheDirectory: paths.cache, modrinth: ModrinthService(client: collisionClient), curseforge: CurseForgeService(apiKey: "fixture", client: collisionClient)).identify([local], refresh: true)
        #expect(collisionResult.matches[local.id]?.map { $0.record.provider } == ["modrinth"])
    }
    @Test func unmatchedFilesAreCachedButChangedBytesAreLookedUpAgain() async throws {
        let (paths, id, _) = try ContentManagerTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let local = try file(paths, id: id)
        let server = EndpointHTTPFixture(["api.modrinth.com/v2/version_files": Data("{}".utf8)])
        defer { server.close() }
        let service = ContentIdentificationService(cacheDirectory: paths.cache, modrinth: ModrinthService(client: HTTPClient(session: server.session)))
        let first = try await service.identify([local])
        #expect(first.matches.isEmpty && first.failures.isEmpty)
        _ = try await service.identify([local])
        #expect(server.requests.count == 1)
        try Data("other".utf8).write(to: local.url)
        _ = try await service.identify([local])
        #expect(server.requests.count == 2)
    }
    @Test func associationPreservesFilenameDisabledStateAndAcquisitionSource() async throws {
        let (paths, id, manager) = try ContentManagerTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let local = try file(paths, id: id), digest = try ContentFileDigest.read(local.url)
        let server = EndpointHTTPFixture(try responses(digest)); defer { server.close() }
        let result = try await ContentIdentificationService(cacheDirectory: paths.cache, modrinth: ModrinthService(client: HTTPClient(session: server.session))).identify([local])
        #expect(try await manager.associate([local], matches: result.matches).isEmpty)
        let record = try #require(await manager.records().first)
        #expect(record.provider == "modrinth" && record.installationSource == "local")
        #expect(record.filename == "renamed.jar" && !record.enabled && record.sha512 == digest.sha512)
        #expect(try Data(contentsOf: local.url) == Data("hello".utf8))
        let fixture = ContentManagerTests()
        try await manager.install([fixture.plan(paths, project: "project", version: "v2", file: "new.jar", text: "updated")])
        let updated = try #require(await manager.scan(.mod).first)
        #expect(!updated.enabled && updated.managed?.installationSource == "local" && updated.filename == "new.jar")
    }
    @Test func associationRejectsStaleFilesAndSkipsDuplicateProjects() async throws {
        let (paths, id, manager) = try ContentManagerTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let first = try file(paths, id: id, name: "a.jar"), second = try file(paths, id: id, name: "b.jar")
        let digest = try ContentFileDigest.read(first.url)
        let server = EndpointHTTPFixture(try responses(digest)); defer { server.close() }
        let result = try await ContentIdentificationService(cacheDirectory: paths.cache, modrinth: ModrinthService(client: HTTPClient(session: server.session))).identify([first, second])
        #expect(try await manager.associate([first, second], matches: result.matches).count == 2)
        #expect(try await manager.records().isEmpty)
        try Data("other".utf8).write(to: first.url)
        await #expect(throws: (any Error).self) { try await manager.associate([first], matches: result.matches) }
        #expect(try await manager.records().isEmpty)
    }
    @Test func curseforgeWhitespaceFilteringDoesNotChangeCryptographicIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try Data("hello".utf8).write(to: a); try Data("h\te l\rl\no ".utf8).write(to: b)
        let first = try ContentFileDigest.read(a), second = try ContentFileDigest.read(b)
        #expect(first.fingerprint == second.fingerprint && first.sha512 != second.sha512)
    }
}
