import Foundation
import Testing
@testable import RuriCore

struct ServiceEndpointTests {
    @Test func rawPathAndQueryValuesCannotChangeTheRouteOrHost() throws {
        let value = "中文 a/b?x=1#f%2F", base = URL(string: "https://example.test/api")!
        let url = try EndpointURL.build(base: base, path: ["project", value], query: [.init(name: "q", value: "C++ & x=y #f%")])
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "example.test" && parts.fragment == nil)
        #expect(parts.percentEncodedPath.hasSuffix("a%2Fb%3Fx=1%23f%252F"))
        #expect(parts.queryItems == [.init(name: "q", value: "C++ & x=y #f%")])
        #expect(parts.percentEncodedQuery?.contains("%2B%2B") == true)
        for invalid in ["", ".", "..", "line\nbreak", "nul\0"] {
            #expect(throws: (any Error).self) { try EndpointURL.build(base: base, path: [invalid]) }
        }
    }
    @Test func loaderAndAssetURLsValidateAndEncodeIdentifiers() throws {
        #expect(try LoaderEndpoints.profile(loader: .fabric, game: "1.21.1", version: "0.19.5").absoluteString == "https://meta.fabricmc.net/v2/versions/loader/1.21.1/0.19.5/profile/json")
        #expect(try LoaderEndpoints.versions(loader: .quilt, game: "1.20.1").absoluteString == "https://meta.quiltmc.org/v3/versions/loader/1.20.1")
        #expect(try LoaderEndpoints.profile(loader: .quilt, game: "1.20.1", version: "0.29.2").path == "/v3/versions/loader/1.20.1/0.29.2/profile/json")
        let hash = String(repeating: "a", count: 40)
        #expect(try MinecraftEndpoints.asset(hash: hash).absoluteString == "https://resources.download.minecraft.net/aa/" + hash)
        #expect(throws: (any Error).self) { try MinecraftEndpoints.asset(hash: "../../invalid") }
        #expect(throws: (any Error).self) { try LoaderEndpoints.profile(loader: .forge, game: "1.21.1", version: "52.1.16") }
        #expect(throws: (any Error).self) { try ForgeCatalog.installerURL(loader: .neoforge, game: "1.21.1", version: "..") }
    }
    @Test func modrinthCallsShareEndpointsAndEncodeFilters() async throws {
        let stub = EndpointHTTPFixture(["api.modrinth.com/v2/search": Data(#"{"hits":[],"total_hits":0}"#.utf8), "api.modrinth.com/v2/project/project id/version": Data("[]".utf8)])
        defer { stub.close() }
        let service = ModrinthService(client: HTTPClient(session: stub.session))
        _ = try await service.search("C++ 中文 & 100%", type: "mod", offset: 20)
        _ = try await service.versions(project: "project id", game: "1.21.1", loader: "fabric")
        let requests = stub.requests
        let query = try #require(URLComponents(url: requests[0].url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(.init(name: "query", value: "C++ 中文 & 100%")))
        #expect(query.contains(.init(name: "facets", value: #"[["project_type:mod"]]"#)))
        #expect(query.contains(.init(name: "offset", value: "20")))
        let versions = try #require(URLComponents(url: requests[1].url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(versions == [.init(name: "game_versions", value: #"["1.21.1"]"#), .init(name: "loaders", value: #"["fabric"]"#)])
    }
    @Test func projectLinksAndAuthenticatedRedirectsStayOnTheirService() throws {
        let modrinth = try #require(ModrinthEndpoints.projectPage(type: "mod", identifier: "name/with?query#fragment"))
        #expect(modrinth.absoluteString == "https://modrinth.com/mod/name%2Fwith%3Fquery%23fragment")
        #expect(ModrinthEndpoints.projectPage(type: "unknown", identifier: "project") == nil)
        #expect(ModrinthEndpoints.projectPage(type: "mod", identifier: "..") == nil)
        var data = CurseForgeTests().project(7)
        for address in ["https://evil.test/project", "https://user:secret@www.curseforge.com/project", "https://www.curseforge.com:444/project"] {
            data["links"] = ["websiteUrl": address]
            let project = try JSONDecoder().decode(CurseForgeProject.self, from: JSONSerialization.data(withJSONObject: data))
            #expect(project.page(for: 70).absoluteString == "https://www.curseforge.com/minecraft/mc-mods/project-7/files/70")
        }
        data["links"] = ["websiteUrl": "https://curseforge.com/minecraft/mc-mods/actual-slug?tracking=1#tab"]
        let project = try JSONDecoder().decode(CurseForgeProject.self, from: JSONSerialization.data(withJSONObject: data))
        #expect(project.page(for: 70).absoluteString == "https://curseforge.com/minecraft/mc-mods/actual-slug/files/70")
        for bad in ["https://api.curseforge.com.evil.test/v1", "http://api.curseforge.com/v1", "https://api.curseforge.com:444/v1", "https://user@api.curseforge.com/v1"] {
            #expect(!CurseForgeEndpoints.allowsAPI(URL(string: bad)!))
        }
        #expect(CurseForgeEndpoints.allowsAPI(URL(string: "https://api.curseforge.com:443/v1/mods")!))
    }
}
