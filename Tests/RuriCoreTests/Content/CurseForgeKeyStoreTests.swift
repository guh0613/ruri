import Foundation
import Testing
@testable import RuriCore

struct CurseForgeKeyStoreTests {
    @Test func customKeyOverridesBundledKeyAndRemovalRestoresDefault() throws {
        #expect(try CurseForgeKeyStore.resolve(bundledKey: "bundled", customKey: { "custom" }) == "custom")
        #expect(try CurseForgeKeyStore.resolve(bundledKey: "bundled", customKey: { nil }) == "bundled")
        #expect(throws: (any Error).self) { try CurseForgeKeyStore.resolve(bundledKey: nil, customKey: { nil }) }
    }

    @Test func keychainErrorsDoNotSilentlyFallBack() {
        struct KeychainFailure: Error {}
        #expect(throws: KeychainFailure.self) {
            try CurseForgeKeyStore.resolve(bundledKey: "bundled", customKey: { throw KeychainFailure() })
        }
        #expect(throws: (any Error).self) {
            try CurseForgeKeyStore.resolve(bundledKey: "bundled", customKey: { "" })
        }
    }

    @Test func keysAreLiteralTokensWithoutHeaderInjection() throws {
        #expect(try CurseForgeKeyStore.validated(" $2a$example+token/= \n") == "$2a$example+token/=")
        for key in ["", " \n", "key\r\nHeader: value", "key\0value", "key\tvalue", "key value", "密钥"] {
            #expect(throws: (any Error).self) { try CurseForgeKeyStore.validated(key) }
        }
    }

    @Test func readsOnlyTheDedicatedApplicationResource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        let contents = root.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.ruri.test.\(UUID().uuidString)", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let resource = resources.appendingPathComponent("RuriServices.plist")
        try PropertyListSerialization.data(fromPropertyList: ["CurseForgeAPIKey": "$bundled&key"], format: .xml, options: 0).write(to: resource)
        let bundle = try #require(Bundle(url: root))
        #expect(CurseForgeKeyStore.bundledKey(in: bundle) == "$bundled&key")
        try PropertyListSerialization.data(fromPropertyList: ["CurseForgeAPIKey": "invalid\nkey"], format: .xml, options: 0).write(to: resource)
        #expect(CurseForgeKeyStore.bundledKey(in: bundle) == nil)
        try FileManager.default.removeItem(at: resource)
        #expect(CurseForgeKeyStore.bundledKey(in: bundle) == nil)
    }
}
