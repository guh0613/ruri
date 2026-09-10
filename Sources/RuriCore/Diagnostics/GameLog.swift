import Foundation

/// Mojang's official Log4j configuration emits XML events. Turn those events into
/// readable lines while preserving ordinary native/JVM stderr and stack traces.
public struct GameLogFormatter: Sendable {
    private var event = ""
    public init() {}
    public mutating func consume(_ input: String) -> [String] {
        let line = input.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        if event.isEmpty, !line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<log4j:Event ") { return [line] }
        event += line + "\n"
        if event.utf8.count > 1024 * 1024 { let raw = event; event = ""; return [raw] }
        guard line.contains("</log4j:Event>") else { return [] }
        let raw = event; event = ""
        let delegate = LogEventParser()
        let parser = XMLParser(data: Data(raw.utf8)); parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !delegate.message.isEmpty else { return [raw] }
        let prefix = "[\(delegate.thread)/\(delegate.level)]"
        var text = "\(prefix) \(delegate.message.trimmingCharacters(in: .newlines))"
        if !delegate.throwable.isEmpty { text += "\n" + delegate.throwable }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }
    public mutating func flush() -> [String] { defer { event = "" }; return event.isEmpty ? [] : [event] }
}
private final class LogEventParser: NSObject, XMLParserDelegate {
    var thread = "main"; var level = "INFO"; var message = ""; var throwable = ""; var current = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        current = elementName
        if elementName == "log4j:Event" { thread = attributes["thread"] ?? "main"; level = attributes["level"] ?? "INFO" }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { current = "" }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { append(String(decoding: CDATABlock, as: UTF8.self)) }
    func parser(_ parser: XMLParser, foundCharacters string: String) { append(string) }
    private func append(_ text: String) {
        if current == "log4j:Message" { message += text }
        if current == "log4j:Throwable" { throwable += text }
    }
}
