import Foundation
import CoreFoundation
import ZIPFoundation

public struct LocalPackMetadata: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case valid, missingMetadata, invalidMetadata, missingShaders, invalidArchive }
    public var state: State
    public var summary: String?
    public var iconPath: String?
    public var format: ResourcePackFormatDeclaration?
    public var requiredIrisFeatures: [String] = []

    static func read(_ url: URL, kind: ContentKind, isDirectory: Bool) -> Self {
        var metadata: Data?, properties: Data?, icon: String?, hasShaders = false, hasMetadata = false
        if isDirectory {
            metadata = readFile("pack.mcmeta", in: url)
            hasMetadata = FileManager.default.fileExists(atPath: url.appendingPathComponent("pack.mcmeta").path)
            if let stamp = LocalContentStamp.read(url.appendingPathComponent("pack.png")), stamp.size <= 4 * 1024 * 1024 { icon = "pack.png" }
            properties = readFile("shaders/shaders.properties", in: url)
            if let shaders = try? LauncherPaths.safePath("shaders", within: url) {
                hasShaders = (try? shaders.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
        } else {
            let archive: Archive
            do { archive = try Archive(url: url, accessMode: .read) } catch { return Self(state: .invalidArchive) }
            var entries: [String: ZIPFoundation.Entry] = [:]
            var shaderRoots = Set<String>()
            for entry in archive {
                if Task.isCancelled { return Self(state: .invalidArchive) }
                let path = entry.path
                if ["pack.mcmeta", "pack.png", "shaders/shaders.properties"].contains(path), entries[path] == nil { entries[path] = entry }
                if kind == .shader {
                    let parts = path.split(separator: "/")
                    if parts.first == "shaders", parts.count > 1 || entry.type == .directory { shaderRoots.insert("") }
                    else if parts.count >= 2, parts[1] == "shaders", parts[0] != "..", parts.count > 2 || entry.type == .directory {
                        shaderRoots.insert(String(parts[0]) + "/")
                        if path.hasSuffix("/shaders/shaders.properties") { entries[path] = entry }
                    }
                }
            }
            metadata = extract(entries["pack.mcmeta"], from: archive)
            hasMetadata = entries["pack.mcmeta"] != nil
            if let entry = entries["pack.png"], entry.type == .file, entry.uncompressedSize <= 4 * 1024 * 1024 { icon = "pack.png" }
            hasShaders = !shaderRoots.isEmpty
            let root = shaderRoots.contains("") ? "" : shaderRoots.sorted().first
            properties = root.flatMap { extract(entries[$0 + "shaders/shaders.properties"], from: archive) }
        }
        var result = Self(state: kind == .shader ? (hasShaders ? .valid : .missingShaders) : (hasMetadata ? .invalidMetadata : .missingMetadata), iconPath: icon)
        if let metadata {
            if let object = (try? JSONSerialization.jsonObject(with: metadata, options: [.json5Allowed])) as? [String: Any], let pack = object["pack"] as? [String: Any] {
                result.summary = plainDescription(pack["description"])
                if kind == .resourcepack { result.state = .valid; result.format = ResourcePackFormatDeclaration(pack) }
            } else if kind == .resourcepack { result.state = .invalidMetadata }
        }
        if kind == .shader, let properties, let text = String(data: properties, encoding: .utf8) ?? String(data: properties, encoding: .isoLatin1) {
            // This is a declared requirement, not a guess about loader compatibility.
            let unfolded = text.replacingOccurrences(of: "\\\r\n", with: "").replacingOccurrences(of: "\\\n", with: "")
            for line in unfolded.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, parts[0] == "iris.features.required" {
                    result.requiredIrisFeatures = parts[1].split(whereSeparator: \.isWhitespace).map(String.init)
                }
            }
        }
        return result
    }

    public static func iconData(at url: URL, path: String, isDirectory: Bool) -> Data? {
        isDirectory ? readFile(path, in: url, limit: 4 * 1024 * 1024) : LocalModMetadata.iconData(at: url, path: path)
    }
    static func readFile(_ path: String, in directory: URL, limit: Int = 1024 * 1024) -> Data? {
        guard LocalContentStamp.read(directory.appendingPathComponent(path)) != nil,
              let url = try? LauncherPaths.safePath(path, within: directory),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= limit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return data
    }
    static func extract(_ entry: ZIPFoundation.Entry?, from archive: Archive, limit: UInt64 = 1024 * 1024) -> Data? {
        guard let entry, entry.type == .file, entry.uncompressedSize <= limit else { return nil }
        var data = Data()
        do {
            let crc = try archive.extract(entry) { chunk in try Task.checkCancellation(); data.append(chunk) }
            return crc == entry.checksum ? data : nil
        } catch { return nil }
    }
    private static func plainDescription(_ value: Any?) -> String? {
        var remaining = 512
        func text(_ value: Any?, depth: Int) -> String {
            guard depth < 32, remaining > 0 else { return "" }; remaining -= 1
            if let value = value as? String { return value }
            if let values = value as? [Any] { return values.map { text($0, depth: depth + 1) }.joined() }
            if let object = value as? [String: Any] {
                return text(object["text"] ?? object["fallback"] ?? object["translate"], depth: depth + 1) + text(object["extra"], depth: depth + 1)
            }
            return ""
        }
        let result = text(value, depth: 0).replacingOccurrences(of: "§[0-9A-FK-ORXa-fk-orx]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : String(result.prefix(16_384))
    }
}

public struct ResourcePackFormat: Codable, Equatable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public var description: String { minor == 0 || minor == Int32.max ? String(major) : "\(major).\(minor)" }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.major == rhs.major ? lhs.minor < rhs.minor : lhs.major < rhs.major }
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= Double(Int32.max), number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.intValue
    }
    static func read(_ value: Any?, maximum: Bool = false) -> Self? {
        if let major = integer(value) { return Self(major: major, minor: maximum ? Int(Int32.max) : 0) }
        guard let parts = value as? [Any], (1...2).contains(parts.count), let major = integer(parts[0]) else { return nil }
        if parts.count == 1 { return Self(major: major, minor: maximum ? Int(Int32.max) : 0) }
        return integer(parts[1]).map { Self(major: major, minor: $0) }
    }
}

public enum ResourcePackCompatibility: Sendable {
    case compatible, tooOld, tooNew, invalid, missingMetadata, unknown
    public var isWarning: Bool { switch self { case .compatible, .unknown: false; default: true } }
}

public struct ResourcePackFormatDeclaration: Codable, Equatable, Sendable {
    let legacy: Int?
    let supportedMinimum: Int?
    let supportedMaximum: Int?
    let minimum: ResourcePackFormat?
    let maximum: ResourcePackFormat?
    let malformed: Bool
    init(_ pack: [String: Any]) {
        legacy = ResourcePackFormat.integer(pack["pack_format"])
        minimum = ResourcePackFormat.read(pack["min_format"])
        maximum = ResourcePackFormat.read(pack["max_format"], maximum: true)
        let supported = pack["supported_formats"]
        if let single = ResourcePackFormat.integer(supported) { supportedMinimum = single; supportedMaximum = single }
        else if let range = supported as? [Any], range.count == 2 {
            supportedMinimum = ResourcePackFormat.integer(range[0]); supportedMaximum = ResourcePackFormat.integer(range[1])
        } else if let range = supported as? [String: Any] {
            supportedMinimum = ResourcePackFormat.integer(range["min_inclusive"]); supportedMaximum = ResourcePackFormat.integer(range["max_inclusive"])
        } else { supportedMinimum = nil; supportedMaximum = nil }
        malformed = (pack["pack_format"] != nil && legacy == nil) || (pack["min_format"] != nil && minimum == nil) ||
            (pack["max_format"] != nil && maximum == nil) || (supported != nil && (supportedMinimum == nil || supportedMaximum == nil))
    }
    public var displayRange: String? {
        if let minimum, let maximum { return minimum.description == maximum.description ? minimum.description : "\(minimum) – \(maximum)" }
        if let min = supportedMinimum, let max = supportedMaximum { return min == max ? String(min) : "\(min) – \(max)" }
        return legacy.map(String.init)
    }
    public func compatibility(with game: ResourcePackFormat?) -> ResourcePackCompatibility {
        guard !malformed else { return .invalid }
        guard let game else { return .unknown }
        guard let range = range(for: game) else { return .invalid }
        if game < range.lowerBound { return .tooNew }
        if game > range.upperBound { return .tooOld }
        return .compatible
    }
    private func range(for game: ResourcePackFormat) -> ClosedRange<ResourcePackFormat>? {
        guard !malformed else { return nil }
        func range(_ min: Int, _ max: Int) -> ClosedRange<ResourcePackFormat>? {
            guard min > 0, min <= max else { return nil }
            return ResourcePackFormat(major: min, minor: 0)...ResourcePackFormat(major: max, minor: Int(Int32.max))
        }
        if game.major < 65 {
            guard let legacy, legacy > 0 else { return nil }
            if game.major > 15, let min = supportedMinimum, let max = supportedMaximum { return range(min, max) }
            return range(legacy, legacy)
        }
        if let minimum, let maximum {
            guard minimum.major > 0, minimum <= maximum else { return nil }
            if minimum.major < 65 {
                guard let legacy, legacy >= 15, legacy >= minimum.major, legacy <= maximum.major,
                      supportedMinimum == minimum.major, supportedMaximum == maximum.major || supportedMaximum == 64 else { return nil }
            } else {
                guard supportedMinimum == nil else { return nil }
                if let legacy, legacy < minimum.major || legacy > maximum.major { return nil }
            }
            return minimum...maximum
        }
        guard minimum == nil, maximum == nil, let legacy, legacy > 0, legacy < 65 else { return nil }
        if let min = supportedMinimum, let max = supportedMaximum {
            guard max < 65, legacy >= 15, legacy >= min, legacy <= max else { return nil }
            return range(min, max)
        }
        return range(legacy, legacy)
    }
}
