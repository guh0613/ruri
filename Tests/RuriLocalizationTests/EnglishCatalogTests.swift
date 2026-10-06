import Foundation
import Testing
@testable import RuriLocalization

struct EnglishCatalogTests {
    @Test func everyShippingEnglishMessageIsPresentAndFormatsSafely() throws {
        #expect(LocalizationContext.supportedLanguages.contains("en"))
        let bundle = try #require(LocalizationResources.bundle)
        let path = try #require(bundle.url(forResource: "en", withExtension: "lproj"))
        let english = try #require(Bundle(url: path))
        let context = LocalizationContext(language: "en", region: "en_US")
        for (identity, definition) in MessageCatalog.definitions {
            let parts = identity.split(separator: ":", maxSplits: 1).map(String.init)
            let template = english.localizedString(forKey: parts[1], value: "MISSING", table: parts[0])
            #expect(template != "MISSING", "Missing English: \(identity)")
            for count: Int64 in [0, 1, 2, 5] {
                let arguments = definition.arguments.map { kind -> LocalizedMessage.Argument in
                    switch kind {
                    case .text: .text("Value %@ 100%")
                    case .integer: .integer(count)
                    case .decimal: .decimal(1.5)
                    }
                }
                let rendered = context.string(.init(key: parts[1], table: parts[0], fallback: definition.fallback, arguments: arguments))
                #expect(rendered.range(of: #"\p{Han}"#, options: .regularExpression) == nil, "Chinese fallback: \(identity)")
                #expect(!rendered.contains("#@"), "Unexpanded plural: \(identity)")
                if definition.arguments.contains(where: { if case .text = $0 { true } else { false } }) {
                    #expect(rendered.contains("Value %@ 100%"), "Missing or reinterpreted text argument: \(identity)")
                }
            }
        }
    }

    @Test func compiledCountsUseSingularAndPluralForms() {
        let english = LocalizationContext(language: "en", region: "en_US")
        #expect(english.string(Messages.Common.fileCount(1)) == "1 file")
        #expect(english.string(Messages.Common.fileCount(3)) == "3 files")
        #expect(english.string(Messages.Servers.filteredServerCount(1, 3)) == "1 / 3 servers")
        #expect(english.string(Messages.Servers.filteredServerCount(1, 1)) == "1 / 1 server")
        #expect(english.string(Messages.Discovery.loadedVersions(1, 3)) == "Loaded 1 file out of 3")
        #expect(english.string(Messages.Discovery.loadedVersions(2, 3)) == "Loaded 2 files out of 3")
        #expect(english.string(Messages.CLIExperience.page(1, 0)) == "Showing 1 item, offset 0.")
        #expect(english.string(Messages.CLIExperience.page(3, 0)) == "Showing 3 items, offset 0.")
    }
}
