import Foundation
import Testing
@testable import RuriCore

struct NetworkRoutingTests {
    @Test func publicArtifactMirrorsPreserveExactPaths() throws {
        for (input, path) in [
            ("https://piston-data.mojang.com/v1/objects/abc/client.jar", "/v1/objects/abc/client.jar"),
            ("https://resources.download.minecraft.net/ab/abcdef", "/assets/ab/abcdef"),
            ("https://libraries.minecraft.net/org/lwjgl/a.jar", "/libraries/org/lwjgl/a.jar"),
            ("https://maven.neoforged.net/releases/net/a%20b.jar", "/maven/net/a%20b.jar"),
            ("https://meta.fabricmc.net/v2/versions/loader/1.21.1", "/fabric-meta/v2/versions/loader/1.21.1")
        ] {
            let url = URL(string: input)!
            let candidates = DownloadSource.bmclapi.candidates(for: url)
            #expect(candidates.count == 2); #expect(candidates[1] == url)
            #expect(candidates[0].host == "bmclapi2.bangbang93.com")
            #expect(URLComponents(url: candidates[0], resolvingAgainstBaseURL: false)?.percentEncodedPath == path)
            #expect(DownloadSource.official.candidates(for: url) == [url])
            #expect(DownloadSource.automatic.candidates(for: url).first == url)
        }
    }
    @Test func modCDNsFallBackToMCIM() throws {
        for (input, path) in [
            ("https://edge.forgecdn.net/files/5012/45/Some%20Mod+1.0.jar", "/files/5012/45/Some%20Mod+1.0.jar"),
            ("https://cdn.modrinth.com/data/AANobbMI/versions/abc/sodium.jar", "/data/AANobbMI/versions/abc/sodium.jar")
        ] {
            let url = URL(string: input)!
            for source in [DownloadSource.automatic, .bmclapi] {
                let candidates = source.candidates(for: url)
                #expect(candidates.count == 2); #expect(candidates[0] == url)
                #expect(candidates[1].host == "mod.mcimirror.top")
                #expect(URLComponents(url: candidates[1], resolvingAgainstBaseURL: false)?.percentEncodedPath == path)
            }
            #expect(DownloadSource.official.candidates(for: url) == [url])
        }
        #expect(DownloadSource.automatic.candidates(for: URL(string: "https://api.curseforge.com/v1/mods/1")!).count == 1)
    }
    @Test func accountAndAuthenticatedRequestsNeverUseMirrors() async throws {
        let routing = NetworkRouting(source: .bmclapi)
        for address in ["https://login.microsoftonline.com/consumers/oauth2/v2.0/token", "https://api.minecraftservices.com/minecraft/profile", "https://api.modrinth.com/v2/search", "https://libraries.minecraft.net.evil.test/a", "https://user:secret@libraries.minecraft.net/a"] {
            let url = URL(string: address)!
            #expect(await routing.candidates(for: url) == [url])
        }
        let url = URL(string: "https://libraries.minecraft.net/test")!
        for field in ["Authorization", "Cookie", "X-API-Key"] {
            var request = URLRequest(url: url); request.setValue("test", forHTTPHeaderField: field)
            #expect(await routing.candidates(for: request) == [url])
        }
        var post = URLRequest(url: url); post.httpMethod = "POST"
        #expect(await routing.candidates(for: post) == [url])
    }
}
