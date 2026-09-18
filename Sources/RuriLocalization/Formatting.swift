import Foundation

public enum LocalizedFormat {
    public static func number<T: BinaryInteger>(_ value: T) -> String {
        Int64(clamping: value).formatted(.number.locale(LocalizationContext.current.formatLocale))
    }
    public static func compactNumber(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).locale(LocalizationContext.current.formatLocale))
    }
    public static func bytes(_ value: Int64, memory: Bool = false) -> String {
        value.formatted(.byteCount(style: memory ? .memory : .file).locale(LocalizationContext.current.formatLocale))
    }
    public static func date(_ value: Date, date: Date.FormatStyle.DateStyle = .abbreviated,
                            time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        value.formatted(Date.FormatStyle(date: date, time: time).locale(LocalizationContext.current.formatLocale))
    }
    public static func relative(_ value: Date) -> String {
        value.formatted(.relative(presentation: .named).locale(LocalizationContext.current.formatLocale))
    }
    public static func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(LocalizationContext.current.formatLocale))
    }
    /// A share of a whole, as a fraction in 0...1.
    public static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let clamped = min(1, max(0, value))
        return clamped.formatted(.percent.precision(.fractionLength(clamped > 0 && clamped < 0.01 ? 1 : 0)).locale(LocalizationContext.current.formatLocale))
    }
    public static func list(_ values: [String]) -> String {
        values.formatted(.list(type: .and).locale(LocalizationContext.current.formatLocale))
    }
    public static func publishedDate(_ value: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        return parsed.map { date($0, time: .omitted) } ?? value
    }
}
