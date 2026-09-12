import RuriLocalization
import Foundation

public struct MinecraftLibrarySelection: Sendable {
    public let manifest: VersionManifest
    public let libraries: [MinecraftLibraryDeclaration]
    public let discarded: [MinecraftDiscardedLibrary]
}

public struct MinecraftDiscardedLibrary: Sendable {
    public enum Reason: String, Sendable { case olderVersion, duplicateDeclaration }
    public let name: String
    public let selectedName: String
    public let reason: Reason
}

extension MinecraftManifestResolution {
    public func selectingLibraries() throws -> MinecraftLibrarySelection {
        let selection = try MinecraftLibrarySelector.select(libraries)
        var result = manifest
        // HMCL treats empty rule lists as unrestricted. Normalize them at the
        // discovery boundary while keeping Ruri's ordinary manifest rules intact.
        let libraries = selection.libraries.map { declaration -> MinecraftLibraryDeclaration in
            let library = declaration.library
            let normalized = Library(name: library.name, downloads: library.downloads, url: library.url,
                                     rules: library.rules?.isEmpty == true ? nil : library.rules, natives: library.natives, extract: library.extract)
            return .init(library: normalized, localFile: declaration.localFile, sourceMetadata: declaration.sourceMetadata)
        }
        result.libraries = libraries.map(\.library)
        func arguments(_ input: [LaunchArgument]?) -> [LaunchArgument]? {
            input?.flatMap { argument in
                if case .conditional(let rules, let values) = argument, rules.isEmpty { return values.map(LaunchArgument.text) }
                return [argument]
            }
        }
        if var existing = result.arguments {
            existing.jvm = arguments(existing.jvm); existing.game = arguments(existing.game); result.arguments = existing
        }
        return .init(manifest: result, libraries: libraries, discarded: selection.discarded)
    }
}

enum MinecraftLibrarySelector {
    struct Selection {
        let libraries: [MinecraftLibraryDeclaration]
        let discarded: [MinecraftDiscardedLibrary]
    }
    private struct Group: Hashable {
        let artifact: String
        let rules: Data
    }
    private struct Candidate {
        let declaration: MinecraftLibraryDeclaration
        let version: String
        let native: Bool
        let richness: Int
        var name: String { declaration.library.name }
    }
    private struct Discarded {
        let candidate: Candidate
        let group: Group
    }
    private struct Versions {
        var latest: String
        var slots: [Int]
    }

    static func select(_ input: [MinecraftLibraryDeclaration]) throws -> Selection {
        guard input.count <= 10_000 else { throw RuriError.message(Messages.CoreMinecraftLibrarySelection.selectText1) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var groups: [Group: Versions] = [:], slots: [Candidate?] = [], discarded: [Discarded] = []
        for declaration in input {
            try Task.checkCancellation()
            let library = declaration.library
            _ = try Library.mavenPath(library.name)
            let coordinate = library.name.split(separator: "@", maxSplits: 1)[0].split(separator: ":").map(String.init)
            let version = coordinate[2]
            guard library.name.utf8.count <= 2_048, version.utf8.count <= 256 else { throw RuriError.message(Messages.CoreMinecraftLibrarySelection.versionText1) }
            let key = Group(artifact: coordinate.prefix(2).joined(separator: ":"), rules: try encoder.encode(library.rules))
            let native = library.natives != nil || library.downloads?.classifiers?.keys.contains(where: { $0.hasPrefix("native") }) == true ||
                (coordinate.count == 4 && coordinate[3].hasPrefix("natives-"))
            let candidate = Candidate(declaration: declaration, version: version, native: native, richness: try richness(declaration, encoder: encoder))
            guard var group = groups[key] else {
                groups[key] = .init(latest: version, slots: [slots.count]); slots.append(candidate); continue
            }
            switch MinecraftDependencyVersion.compare(version, group.latest) {
            case .orderedAscending:
                discarded.append(.init(candidate: candidate, group: key))
            case .orderedDescending:
                // Replace all older variants in this rules group. Keeping an
                // old native alongside a newer Java library can break LWJGL.
                for index in group.slots {
                    let previous = slots[index]!
                    discarded.append(.init(candidate: previous, group: key))
                    slots[index] = nil
                }
                let first = group.slots[0]; slots[first] = candidate
                group.latest = version; group.slots = [first]; groups[key] = group
            case .orderedSame:
                if let index = group.slots.first(where: { slots[$0]?.name == candidate.name && slots[$0]?.native == candidate.native }) {
                    let previous = slots[index]!
                    if candidate.richness > previous.richness { slots[index] = candidate }
                    discarded.append(.init(candidate: candidate.richness > previous.richness ? previous : candidate, group: key))
                } else {
                    group.slots.append(slots.count); groups[key] = group; slots.append(candidate)
                }
            }
        }
        let explanations = discarded.map { item -> MinecraftDiscardedLibrary in
            let group = groups[item.group]!
            let index = group.slots.first { slots[$0]?.native == item.candidate.native } ?? group.slots[0]
            return .init(name: item.candidate.name, selectedName: slots[index]!.name,
                         reason: MinecraftDependencyVersion.compare(item.candidate.version, group.latest) == .orderedAscending ? .olderVersion : .duplicateDeclaration)
        }
        return .init(libraries: slots.compactMap { $0?.declaration }, discarded: explanations)
    }

    private static func richness(_ declaration: MinecraftLibraryDeclaration, encoder: JSONEncoder) throws -> Int {
        let data: Data
        if let raw = declaration.sourceMetadata,
           let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            let fields: Set<String> = ["name", "url", "downloads", "checksums", "extract", "natives", "rules", "hint", "filename", "MMC-hint", "MMC-filename"]
            var known = object.filter { fields.contains($0.key) && !($0.value is NSNull) }
            for name in ["hint", "filename"] {
                if known[name] == nil { known[name] = known["MMC-" + name] }
                known.removeValue(forKey: "MMC-" + name)
            }
            data = try JSONSerialization.data(withJSONObject: known, options: [.sortedKeys, .withoutEscapingSlashes])
        } else { data = try encoder.encode(declaration.library) }
        return String(decoding: data, as: UTF8.self).utf16.count
    }
}
