import Foundation
import ZIPFoundation
import TOMLDecoder

/// Presentation metadata belongs to the local archive, independently of its download source.
public struct LocalModMetadata: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String?
    public var version: String?
    public var authors: [String] = []
    public var summary: String?
    public var homepage: URL?
    public var iconPath: String?
    public var loaders: [String] = []

    public static func read(_ url: URL) -> Self? {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) } catch { return nil }
        // Archive's path subscript traverses every entry, including for missing paths.
        // Index the handful of manifests together so a JAR's directory is read once.
        let paths: Set<String> = ["META-INF/neoforge.mods.toml", "META-INF/mods.toml", "META-INF/MANIFEST.MF",
                                  "fabric.mod.json", "quilt.mod.json", "litemod.json", "mcmod.info"]
        var entries: [String: ZIPFoundation.Entry] = [:]
        for item in archive {
            if Task.isCancelled { return nil }
            let path = item.path
            if paths.contains(path), entries[path] == nil { entries[path] = item }
        }
        var found: [Self] = []
        for (path, loader) in [("META-INF/neoforge.mods.toml", "NeoForge"), ("META-INF/mods.toml", "Forge")] {
            guard let data = extract(entries[path], in: archive), let manifest = try? TOMLDecoder().decode(ForgeManifest.self, from: data),
                  let mod = manifest.mods.first else { continue }
            var version = mod.version
            if version == "${file.jarVersion}" { version = jarVersion(extract(entries["META-INF/MANIFEST.MF"], in: archive)) }
            found.append(Self(id: clean(mod.modId), name: clean(mod.displayName), version: resolvedVersion(version),
                              authors: clean(mod.authors).map { [$0] } ?? [], summary: clean(mod.description),
                              homepage: webURL(mod.displayURL ?? manifest.displayURL), iconPath: clean(mod.logoFile ?? manifest.logoFile), loaders: [loader]))
        }
        for path in ["fabric.mod.json", "quilt.mod.json", "litemod.json", "mcmod.info"] {
            guard let data = extract(entries[path], in: archive), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            var object = json as? [String: Any] ?? [:]
            if path == "mcmod.info" {
                guard let first = ((json as? [[String: Any]]) ?? (object["modList"] as? [[String: Any]]))?.first else { continue }
                object = first
            }
            var info: Self
            if let quilt = object["quilt_loader"] as? [String: Any] {
                let metadata = quilt["metadata"] as? [String: Any] ?? [:]
                let contact = metadata["contact"] as? [String: Any]
                info = Self(id: clean(quilt["id"] as? String), name: clean(metadata["name"] as? String), version: resolvedVersion(quilt["version"] as? String),
                            authors: (metadata["contributors"] as? [String: Any])?.keys.sorted() ?? [], summary: clean(metadata["description"] as? String),
                            homepage: webURL(contact?["homepage"] as? String), iconPath: icon(metadata["icon"]), loaders: ["Quilt"])
            } else {
                let lite = path == "litemod.json", oldForge = path == "mcmod.info"
                let contact = object["contact"] as? [String: Any]
                let people = (object["authors"] ?? object["authorList"]) as? [Any] ?? []
                let authors = people.compactMap { clean(($0 as? String) ?? ($0 as? [String: Any])?["name"] as? String) }
                info = Self(id: clean(object[lite ? "name" : oldForge ? "modid" : "id"] as? String),
                            name: clean((lite ? object["displayName"] ?? object["name"] : object["name"]) as? String),
                            version: resolvedVersion(object["version"] as? String),
                            authors: authors.isEmpty ? clean(object["author"] as? String).map { [$0] } ?? [] : authors,
                            summary: clean(object["description"] as? String), homepage: webURL((contact?["homepage"] ?? object["url"]) as? String),
                            iconPath: icon(object["icon"] ?? object["logoFile"]), loaders: [lite ? "LiteLoader" : oldForge ? "Forge" : "Fabric"])
            }
            if info.id != nil || info.name != nil { found.append(info) }
        }
        guard var primary = found.first else { return nil }
        primary.loaders = Array(Set(found.flatMap(\.loaders))).sorted()
        return primary
    }

    public static func iconData(at url: URL, path: String) -> Data? {
        let archive: Archive
        do { archive = try Archive(url: url, accessMode: .read) } catch { return nil }
        return extract(archive[path], in: archive, limit: 4 * 1024 * 1024)
    }

    private static func extract(_ entry: ZIPFoundation.Entry?, in archive: Archive, limit: UInt64 = 1024 * 1024) -> Data? {
        guard let entry, entry.type == .file, entry.uncompressedSize <= limit else { return nil }
        var data = Data()
        do { _ = try archive.extract(entry) { data.append($0) }; return data } catch { return nil }
    }
    private static func clean(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    private static func resolvedVersion(_ value: String?) -> String? {
        guard let value = clean(value), !value.contains("${") else { return nil }
        return value
    }
    private static func webURL(_ value: String?) -> URL? { value.flatMap(CatalogMetadata.webURL) }
    private static func icon(_ value: Any?) -> String? {
        if let string = value as? String { return clean(string) }
        if let sizes = value as? [String: String] {
            return sizes.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.first(where: { (Int($0) ?? 0) >= 64 }).flatMap { sizes[$0] }
                ?? sizes.keys.sorted().last.flatMap { sizes[$0] }
        }
        return nil
    }
    private static func jarVersion(_ data: Data?) -> String? {
        guard let data, let text = String(data: data, encoding: .utf8) else { return nil }
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "")
        for line in unfolded.components(separatedBy: "\n") {
            if line.isEmpty { break }
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "implementation-version" { return clean(String(parts[1])) }
        }
        return nil
    }
    private struct ForgeManifest: Decodable {
        struct Mod: Decodable {
            let modId: String
            let displayName: String?
            let version: String?
            let authors: String?
            let description: String?
            let displayURL: String?
            let logoFile: String?
        }
        let mods: [Mod]
        let displayURL: String?
        let logoFile: String?
    }
}
