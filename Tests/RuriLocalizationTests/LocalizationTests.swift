import Foundation
import Testing
@testable import RuriLocalization

struct LocalizationTests {
    @Test func languageMatchingAndMissingResources() {
        let available = ["de", "en", "zh-Hans", "zh-Hant"]
        #expect(LocalizationContext.resolve("zh-TW", available: available, preferences: []) == "zh-Hant")
        #expect(LocalizationContext.resolve("en-GB", available: available, preferences: []) == "en")
        #expect(LocalizationContext.resolve("unknown", available: available, preferences: []) == "zh-Hans")
        #expect(LocalizationContext.resolve("system", available: available, preferences: ["en-AU"]) == "en")
        let context = LocalizationContext(language: "fr", resources: nil)
        #expect(context.string(Messages.Common.cancel) == "取消")
        #expect(context.string(.verbatim("common.cancel")) == "common.cancel")
        #expect(context.string(.init(key: "future.message", table: "Common", fallback: "old recorded text")) == "old recorded text")
        #expect(context.string(.init(key: "common.fileCount", table: "Common", fallback: "invalid data", arguments: [.text("unsafe")])) == "invalid data")
    }

    @Test func pluralRulesArgumentReorderingAndConcurrentContexts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "test.ruri.localization", "CFBundleDevelopmentRegion": "zh-Hans"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Info.plist"))
        for language in ["en", "zh-Hans"] {
            let directory = root.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let cancel = language == "en" ? "Cancel" : "取消"
            try Data(("\"common.cancel\" = \"" + cancel + "\";\n").utf8).write(to: directory.appendingPathComponent("Common.strings"))
        }
        let spec: [String: Any] = [
            "common.fileCount": ["NSStringLocalizedFormatKey": "%#@files@", "files": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld", "one": "%lld file", "other": "%lld files"]],
            "common.filesAndSize": ["NSStringLocalizedFormatKey": "%2$@ across %1$#@files@", "files": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld", "one": "%lld file", "other": "%lld files"]]
        ]
        try PropertyListSerialization.data(fromPropertyList: spec, format: .xml, options: 0).write(to: root.appendingPathComponent("en.lproj/Common.stringsdict"))
        let resources = try #require(Bundle(url: root))
        let english = LocalizationContext(language: "en", region: "en_US", resources: resources)
        let chinese = LocalizationContext(language: "zh-Hans", region: "zh_CN", resources: resources)
        for count: Int64 in [0, 1, 2, 5] {
            let noun = count == 1 ? "file" : "files"
            #expect(english.string(Messages.Common.fileCount(count)) == "\(count) \(noun)")
            #expect(english.string(Messages.Common.filesAndSize(count, "A %@ 100%")) == "A %@ 100% across \(count) \(noun)")
        }
        async let a = LocalizationContext.$current.withValue(english) { await Task.yield(); return Messages.Common.cancel.localized }
        async let b = LocalizationContext.$current.withValue(chinese) { await Task.yield(); return Messages.Common.cancel.localized }
        #expect(await a == "Cancel")
        #expect(await b == "取消")
        #expect(english.string(Messages.Common.done) == "完成")
        let nested = Messages.Common.filesAndSize(2, "").withTextArgument(1, message: Messages.Common.cancel).recorded()
        #expect(english.string(nested) == "Cancel across 2 files")
    }

    @Test func recordingRedactsParametersAndKeepsUnknownMessageReadable() throws {
        let original = Messages.Common.filesAndSize(3, "private-secret")
        let recorded = original.recorded { $0.replacingOccurrences(of: "private-secret", with: "<redacted>") }
        let data = try JSONEncoder().encode(recorded)
        #expect(!String(decoding: data, as: UTF8.self).contains("private-secret"))
        #expect(try JSONDecoder().decode(LocalizedMessage.self, from: data).localized.contains("<redacted>"))
        #expect(recorded.fallback.contains("<redacted>"))
        let unknown = LocalizedMessage(key: "removed.key", table: "Common", fallback: recorded.fallback, arguments: recorded.arguments)
        #expect(unknown.localized == recorded.fallback)
    }

}
