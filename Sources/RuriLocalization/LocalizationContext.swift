import Foundation

public struct LocalizationContext: Sendable {
    public static let baseLanguage = "zh-Hans"
    public static let preferenceKey = "interfaceLanguage"
    public static let systemPreference = "system"
    public static var supportedLanguages: [String] { LocalizationResources.languages }

    public let language: String
    public let regionIdentifier: String
    private let fallbackBundles: [(language: String, bundle: Bundle)]
    public let pseudolocalized: Bool

    /// CLI language is independent of the application's saved UI preference.
    /// Partial CLI translations do not advertise another GUI language.
    public static func commandLine(language: String? = nil) -> LocalizationContext {
        .init(language: language ?? "en", commandLine: true)
    }
    /// The default is immutable for the process. Tasks may scope a different
    /// context without changing another window, monitor, or concurrent test.
    @TaskLocal public static var current: LocalizationContext = .processDefault

    public static let processDefault: LocalizationContext = {
        let environment = ProcessInfo.processInfo.environment
        let preference = Bundle.main.bundleIdentifier == "dev.ruri.launcher"
            ? UserDefaults.standard.string(forKey: preferenceKey) : nil
        #if DEBUG
        let pseudolocalized = environment["RURI_PSEUDOLOCALIZE"] == "1"
        #else
        let pseudolocalized = false
        #endif
        return .init(language: environment["RURI_LANGUAGE"] ?? preference,
                     region: Locale.current.identifier,
                     pseudolocalized: pseudolocalized)
    }()

    public init(language requested: String? = nil, region: String = Locale.current.identifier,
                preferences: [String] = Locale.preferredLanguages, resources: Bundle? = LocalizationResources.bundle,
                pseudolocalized: Bool = false, commandLine: Bool = false, available: [String]? = nil) {
        self.language = Self.resolve(requested, available: available ?? (commandLine ? SupportedLocalizations.commandLineLanguages : SupportedLocalizations.languages), preferences: preferences)
        self.regionIdentifier = region
        self.pseudolocalized = pseudolocalized
        let fallback = self.language.lowercased().hasPrefix("zh-") ? Self.baseLanguage : "en"
        var seen = Set<String>()
        self.fallbackBundles = [self.language, fallback, Self.baseLanguage].compactMap { language in
            guard seen.insert(language).inserted, let bundle = Self.localizationBundle(language, in: resources) else { return nil }
            return (language, bundle)
        }
    }

    public static func savePreference(_ language: String, in preferences: UserDefaults = .standard) {
        preferences.set(language, forKey: preferenceKey)
        if language == systemPreference {
            preferences.removeObject(forKey: "AppleLanguages")
        } else {
            preferences.set([language], forKey: "AppleLanguages")
        }
    }

    public static func resolve(_ requested: String?, available: [String], preferences: [String]) -> String {
        let languages = available.filter { $0.caseInsensitiveCompare("Base") != .orderedSame }
        let choices = requested.flatMap { $0.isEmpty || $0 == systemPreference ? nil : [$0] } ?? preferences
        let matches = Bundle.preferredLocalizations(from: languages, forPreferences: choices + [baseLanguage])
        return matches.first ?? languages.first(where: { $0.caseInsensitiveCompare(baseLanguage) == .orderedSame }) ?? baseLanguage
    }

    private static func localizationBundle(_ language: String, in resources: Bundle?) -> Bundle? {
        guard let resources,
              let name = resources.localizations.first(where: { $0.caseInsensitiveCompare(language) == .orderedSame }),
              let url = resources.url(forResource: name, withExtension: "lproj") else { return nil }
        return Bundle(url: url)
    }

    /// Language controls words and units; the user's region, calendar and time
    /// zone remain independent. Machine-readable data never uses this locale.
    public var formatLocale: Locale { formatLocale(language: language) }

    func formatLocale(language: String) -> Locale {
        var components = Locale.Components(identifier: regionIdentifier)
        components.languageComponents = Locale.Language.Components(identifier: language)
        return Locale(components: components)
    }

    public func string(_ message: LocalizedMessage) -> String {
        guard !message.key.isEmpty else { return message.fallback }
        // Unknown persisted messages are displayed as their recorded fallback.
        // They must not supply an unchecked printf format to Foundation.
        guard let definition = MessageCatalog.definitions[message.table + ":" + message.key],
              definition.accepts(message.arguments) else { return message.fallback }
        let missing = "__RURI_MISSING_LOCALIZATION_817995BA__"
        var template = definition.fallback
        var formatLanguage = Self.baseLanguage
        for (language, bundle) in fallbackBundles {
            let value = bundle.localizedString(forKey: message.key, value: missing, table: message.table)
            if value != missing {
                template = value
                formatLanguage = language
                break
            }
        }
        let rendered = message.format(template, context: self, language: formatLanguage)
        return pseudolocalized ? "⟦" + rendered + " " + String(repeating: "ø", count: min(80, max(8, template.count))) + "⟧" : rendered
    }
}

public struct MessageDefinition: Sendable {
    public enum ArgumentKind: Sendable { case text, integer, decimal }
    public let fallback: String
    public let arguments: [ArgumentKind]
    public init(_ fallback: String, _ arguments: [ArgumentKind] = []) { self.fallback = fallback; self.arguments = arguments }
    func accepts(_ values: [LocalizedMessage.Argument]) -> Bool {
        guard values.count == arguments.count else { return false }
        return zip(arguments, values).allSatisfy { kind, value in
            switch (kind, value) {
            case (.text, .text), (.text, .message), (.integer, .integer), (.decimal, .decimal): true
            default: false
            }
        }
    }
}
