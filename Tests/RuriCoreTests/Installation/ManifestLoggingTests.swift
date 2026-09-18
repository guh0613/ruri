import Foundation
import Testing
@testable import RuriCore

struct ManifestLoggingTests {
    @Test func exportedManifestsKeepLoggingTypeAndRestoreItForOlderRuriInstalls() throws {
        for declaration in [nil, NSNull(), "", "log4j2-xml", "custom-type"] as [Any?] {
            var client: [String: Any] = ["argument": "-Dlog4j.configurationFile=${path}",
                                      "file": ["id": "client.xml", "url": "https://fixture.invalid/client.xml"]]
            client["type"] = declaration
            let raw: [String: Any] = ["id": "1.21.1", "libraries": [], "logging": ["client": client]]
            let manifest = try JSONDecoder().decode(VersionManifest.self, from: JSONSerialization.data(withJSONObject: raw))
            let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
            let logging = try #require(encoded["logging"] as? [String: Any])
            let saved = try #require(logging["client"] as? [String: Any])
            let expected = (declaration as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "log4j2-xml"
            #expect(saved["type"] as? String == expected)
        }
    }

    @Test func resolvesMissingNullAndEmptyIDsFromURLWhilePreservingExplicitIDs() throws {
        for declaration in [nil, NSNull(), "", "custom.xml"] as [Any?] {
            var raw: [String: Any] = ["url": "https://fixture.invalid/objects/hash/client%20config.xml?download=1", "sha1": "hash", "size": 888]
            raw["id"] = declaration
            let file = try JSONDecoder().decode(VersionManifest.Logging.LogFile.self, from: JSONSerialization.data(withJSONObject: raw))
            #expect(file.id == ((declaration as? String) == "custom.xml" ? "custom.xml" : "client config.xml"))
            let roundTrip = try JSONDecoder().decode(VersionManifest.Logging.LogFile.self, from: JSONEncoder().encode(file))
            #expect(roundTrip.id == file.id && roundTrip.url == file.url)
            #expect(roundTrip.sha1 == "hash" && roundTrip.size == 888)
        }
    }

    @Test func rejectsMissingFilenamesAndPathsOutsideLogConfigs() throws {
        let invalid: [[String: Any]] = [
            ["url": "https://fixture.invalid"],
            ["url": "https://fixture.invalid/log_configs/"],
            ["url": "https://fixture.invalid/%2E%2E"],
            ["url": "https://fixture.invalid/bad%5Cname.xml"],
            ["url": "https://fixture.invalid/client.xml", "id": "../outside.xml"],
            ["url": "https://fixture.invalid/client.xml", "id": "/outside.xml"],
            ["url": "https://fixture.invalid/client.xml", "id": 1],
            ["id": "client.xml"]
        ]
        for raw in invalid {
            let data = try JSONSerialization.data(withJSONObject: raw)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(VersionManifest.Logging.LogFile.self, from: data) }
        }
    }
}
