import Foundation
import Testing
@testable import RuriLocalization

struct LocalizationFallbackTests {
    @Test func fallbackUsesTheTranslationLanguageForPluralRules() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "test.ruri.fallback", "CFBundleDevelopmentRegion": "zh-Hans"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: root.appendingPathComponent("Info.plist"))
        let translations: [String: [String: String]] = [
            "fr": ["Common.cancel": "Annuler"],
            "en": ["Common.cancel": "Cancel", "Common.done": "Done"],
            "zh-Hans": ["Common.cancel": "取消", "Common.done": "完成", "Common.language": "语言"],
            "zh-Hant": ["Common.cancel": "取消（繁體）"]
        ]
        for (language, values) in translations {
            let directory = root.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: directory.appendingPathComponent("Common.strings"))
        }
        let spec: [String: Any] = ["Common.fileCount": [
            "NSStringLocalizedFormatKey": "%#@files@",
            "files": ["NSStringFormatSpecTypeKey": "NSStringPluralRuleType", "NSStringFormatValueTypeKey": "lld", "one": "%lld file", "other": "%lld files"]
        ]]
        try PropertyListSerialization.data(fromPropertyList: spec, format: .xml, options: 0).write(to: root.appendingPathComponent("en.lproj/Common.stringsdict"))
        let bundle = try #require(Bundle(url: root))
        let languages = Array(translations.keys)
        let french = LocalizationContext(language: "fr", region: "fr_FR", resources: bundle, available: languages)
        #expect(french.string(Messages.Common.cancel) == "Annuler")
        #expect(french.string(Messages.Common.done) == "Done")
        #expect(french.string(Messages.Common.language) == "语言")
        // French uses singular for zero. English fallback must still use its
        // own rule, while retaining the user's regional number formatting.
        #expect(french.string(Messages.Common.fileCount(0)) == "0 files")
        #expect(french.string(Messages.Common.fileCount(1)) == "1 file")
        #expect(french.string(Messages.Common.fileCount(3)) == "3 files")
        let traditional = LocalizationContext(language: "zh-Hant", resources: bundle, available: languages)
        #expect(traditional.string(Messages.Common.cancel) == "取消（繁體）")
        #expect(traditional.string(Messages.Common.done) == "完成")
        let english = LocalizationContext(language: "en", resources: bundle, available: languages)
        #expect(english.string(Messages.Common.language) == "语言")
        let pseudo = LocalizationContext(language: "fr", resources: bundle, pseudolocalized: true, available: languages)
        #expect(pseudo.string(Messages.Common.done).hasPrefix("⟦Done "))
        #expect(french.string(.init(key: "common.cancel", table: "Common", fallback: "old recorded text")) == "old recorded text")
        #expect(french.string(.init(key: "Common.fileCount", table: "Common", fallback: "invalid data", arguments: [.text("unsafe")])) == "invalid data")
    }

    // Fixed domains: clearing a domain leaves its empty plist behind, so
    // per-run names would accumulate files in ~/Library/Preferences.
    @Test func preferenceIsTheAppLanguagesEntry() throws {
        let suite = "test.ruri.language.preference"
        let preferences = try #require(UserDefaults(suiteName: suite))
        preferences.removePersistentDomain(forName: suite)
        defer { preferences.removePersistentDomain(forName: suite) }
        #expect(LocalizationContext.savedLanguage(in: preferences, domain: suite) == "system")
        LocalizationContext.savePreference("en", in: preferences)
        #expect(preferences.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["en"])
        #expect(LocalizationContext.savedLanguage(in: preferences, domain: suite) == "en")
        // System Settings may store a regional variant of a supported language.
        preferences.set(["en-GB"], forKey: "AppleLanguages")
        #expect(LocalizationContext.savedLanguage(in: preferences, domain: suite) == "en")
        LocalizationContext.savePreference("system", in: preferences)
        #expect(preferences.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        #expect(LocalizationContext.savedLanguage(in: preferences, domain: suite) == "system")
    }

    @Test func legacyPreferenceMigratesOnce() throws {
        let suite = "test.ruri.language.migration"
        let preferences = try #require(UserDefaults(suiteName: suite))
        preferences.removePersistentDomain(forName: suite)
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set("en", forKey: "interfaceLanguage")
        #expect(LocalizationContext.migrateLegacyPreference(in: preferences, domain: suite) == "en")
        #expect(preferences.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["en"])
        #expect(preferences.persistentDomain(forName: suite)?["interfaceLanguage"] == nil)
        #expect(LocalizationContext.migrateLegacyPreference(in: preferences, domain: suite) == nil)
        // A choice made later in System Settings wins over the old key.
        preferences.set("en", forKey: "interfaceLanguage")
        preferences.set(["zh-Hans"], forKey: "AppleLanguages")
        #expect(LocalizationContext.migrateLegacyPreference(in: preferences, domain: suite) == nil)
        #expect(preferences.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["zh-Hans"])
    }
}
