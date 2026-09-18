import Foundation

/// Offline names and encyclopedia links from HMCL's bundled mcmod.cn index.
/// Keep the data's attribution header when updating the resource.
public struct ModNameIndex: Sendable {
    public struct Entry: Equatable, Sendable {
        public let chineseName: String
        public let englishName: String
        public let abbreviation: String
        public let modIDs: [String]
        public let encyclopediaID: String
        public let searchText: String
        let hasChineseName: Bool
        init(chineseName: String, englishName: String, abbreviation: String, modIDs: [String], encyclopediaID: String) {
            self.chineseName = chineseName; self.englishName = englishName; self.abbreviation = abbreviation
            self.modIDs = modIDs; self.encyclopediaID = encyclopediaID
            searchText = [chineseName, englishName, abbreviation].joined(separator: " ")
            hasChineseName = chineseName.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
        }
        public var pageURL: URL? {
            guard !encyclopediaID.isEmpty, encyclopediaID.allSatisfy(\.isNumber) else { return nil }
            return URL(string: "https://www.mcmod.cn/class/\(encyclopediaID).html")
        }
    }
    public static let shared: Self = {
        let text = Bundle.module.url(forResource: "mod_data", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return Self(text: text)
    }()
    private var entries: [Entry] = []
    private var byID: [String: Int] = [:]
    private var ambiguousIDs: Set<String> = []
    private var byName: [String: Int] = [:]
    init(text: String) {
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6 else { continue }
            let entry = Entry(chineseName: fields[3], englishName: fields[4], abbreviation: fields[5], modIDs: fields[2].split(separator: ",").map(String.init), encyclopediaID: fields[1])
            let index = entries.count
            entries.append(entry)
            for id in Set(entry.modIDs) {
                if byID[id] == nil { byID[id] = index }
                else { ambiguousIDs.insert(id) }
            }
            let name = Self.normalized(entry.englishName)
            if !name.isEmpty, byName[name] == nil { byName[name] = index }
        }
    }
    public func match(id: String?, name: String) -> Entry? {
        // Most IDs are unambiguous: no name normalization or second lookup needed.
        if let id, let index = byID[id], !ambiguousIDs.contains(id) { return entries[index] }
        if let index = byName[Self.normalized(name)] {
            let entry = entries[index]
            if id?.isEmpty != false || entry.modIDs.contains(id ?? "") { return entry }
        }
        return id.flatMap { byID[$0] }.map { entries[$0] }
    }
    private static func normalized(_ value: String) -> String {
        var result = ""
        for ch in value.unicodeScalars {
            switch ch.value {
            case 48...57, 65...90, 97...122: result.unicodeScalars.append(ch)
            default:
                if ".+\\".unicodeScalars.contains(ch) { result.unicodeScalars.append(ch) }
                else if CharacterSet.whitespacesAndNewlines.contains(ch) || "':_-/&()[]{}|,!?~•".unicodeScalars.contains(ch) || (0x1F300...0x1FAFF).contains(ch.value) { continue }
                else { return "" }
            }
        }
        return result
    }
}
