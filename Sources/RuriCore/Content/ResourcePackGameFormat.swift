import Foundation
import ZIPFoundation

/// Reads the game's own format number so new releases need no launcher-side table.
public actor ResourcePackGameFormat {
    public static let shared = ResourcePackGameFormat()
    private struct Cached { let format: ResourcePackFormat? }
    private var cache: [String: Cached] = [:]

    public func read(instance: GameInstance, paths: LauncherPaths) -> ResourcePackFormat? {
        let release = instance.gameVersion.split(separator: ".").compactMap { Int($0) }
        if release.count >= 2, release[0] == 1, (6...13).contains(release[1]) {
            let format = release[1] < 9 ? 1 : release[1] < 11 ? 2 : release[1] < 13 ? 3 : 4
            return .init(major: format, minor: 0)
        }
        do {
            try paths.validateBinding(instance)
            let resources = try paths.resources(for: instance)
            var manifest = paths.manifest(instance.id), jarID: String?, seen = Set<String>()
            for _ in 0..<32 {
                try Task.checkCancellation()
                guard seen.insert(manifest.path).inserted,
                      let data = LocalPackMetadata.readFile(manifest.lastPathComponent, in: manifest.deletingLastPathComponent()),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                jarID = jarID ?? object["jar"] as? String
                if let parent = object["inheritsFrom"] as? String {
                    manifest = try LauncherPaths.safePath("\(parent)/\(parent).json", within: resources.versions)
                } else {
                    jarID = jarID ?? (instance.repositoryVersionID != nil ? object["id"] as? String : nil) ?? instance.gameVersion
                    break
                }
            }
            guard let jarID else { return nil }
            let jar = try LauncherPaths.safePath("\(jarID)/\(jarID).jar", within: resources.versions)
            guard let stamp = LocalContentStamp.read(jar) else { return nil }
            if let cached = cache[stamp.key] { return cached.format }
            let format = Self.readJar(jar)
            guard !Task.isCancelled, LocalContentStamp.read(jar) == stamp else { return nil }
            if cache.count >= 32 { cache.removeAll(keepingCapacity: true) }
            cache[stamp.key] = Cached(format: format)
            return format
        } catch { return nil }
    }
    private static func readJar(_ jar: URL) -> ResourcePackFormat? {
        let archive: Archive
        do { archive = try Archive(url: jar, accessMode: .read) } catch { return nil }
        guard let data = LocalPackMetadata.extract(archive["version.json"], from: archive),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let pack = object["pack_version"] as? [String: Any] {
            if let major = ResourcePackFormat.integer(pack["resource_major"]), major >= 65 {
                return .init(major: major, minor: ResourcePackFormat.integer(pack["resource_minor"]) ?? 0)
            }
            return ResourcePackFormat.integer(pack["resource"]).map { .init(major: $0, minor: 0) }
        }
        return ResourcePackFormat.integer(object["pack_version"]).map { .init(major: $0, minor: 0) }
    }
}
