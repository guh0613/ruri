import Foundation

public struct LocalizationContext: Sendable {
    public static let baseLanguage = "zh-Hans"
    public static let preferenceKey = "interfaceLanguage"
    public static let systemPreference = "system"
    public static var supportedLanguages: [String] { LocalizationResources.languages }

    public let language: String
    public let regionIdentifier: String
    private let resources: Bundle?
    private let translated: Bundle?
    private let base: Bundle?
    public let pseudolocalized: Bool

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
                pseudolocalized: Bool = false) {
        self.resources = resources
        self.language = Self.resolve(requested, available: resources?.localizations ?? [Self.baseLanguage], preferences: preferences)
        self.regionIdentifier = region
        self.pseudolocalized = pseudolocalized
        self.translated = Self.localizationBundle(language, in: resources)
        self.base = Self.localizationBundle(Self.baseLanguage, in: resources)
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
    public var formatLocale: Locale {
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
        let value = translated?.localizedString(forKey: message.key, value: missing, table: message.table)
        let fallback = base?.localizedString(forKey: message.key, value: definition.fallback, table: message.table) ?? definition.fallback
        let template = value == nil || value == missing ? fallback : value!
        let rendered = message.format(template, context: self)
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
