import Foundation
import RuriLocalization

public struct MinecraftFolderPreview: Identifiable, Sendable {
    public var id: URL { directory }
    public let directory: URL
    public let suggestedName: String
    public let versions: [MinecraftFolderVersionPreview]
    public var versionNames: [String] { versions.map(\.id) }
    public var issueCount: Int { versions.filter { $0.issue != nil }.count }
}

/// Keep display metadata without retaining the manifests read during discovery.
public struct MinecraftFolderVersionPreview: Identifiable, Sendable {
    public let id: String
    public let subtitle: String
    public let issue: String?
}

public struct MinecraftFolderSuggestion: Identifiable, Sendable {
    public enum Status: Sendable { case detected, added, removed }
    public var id: String { directory.path }
    public let directory: URL
    public let name: String
    public let status: Status
    public let registration: GameDirectory?
}

/// Read-only discovery for the add-folder flow. Search only the chosen location
/// and nearby launcher folders, never recursively through the user's disk.
public enum MinecraftFolderDiscovery {
    /// Merge cached discovery with current registrations. Recorded locations stay
    /// visible even outside the search scope or while their volume is offline.
    public static func suggestions(locations: [URL], directories: [GameDirectory], removedDirectories: [GameDirectory]) -> [MinecraftFolderSuggestion] {
        var result: [MinecraftFolderSuggestion] = [], seen = Set<String>()
        for (records, status) in [(directories, MinecraftFolderSuggestion.Status.added), (removedDirectories, .removed)] {
            for directory in records {
                let url = directory.url.standardizedFileURL
                if seen.insert(url.path).inserted {
                    result.append(.init(directory: url, name: directory.name, status: status, registration: directory))
                }
            }
        }
        for location in locations {
            let url = location.standardizedFileURL
            if seen.insert(url.path).inserted {
                result.append(.init(directory: url, name: suggestedName(for: url, existingNames: []), status: .detected, registration: nil))
            }
        }
        return result
    }

    public static func commonLocations() throws -> [URL] {
        let manager = FileManager.default
        return try commonLocations(home: manager.homeDirectoryForCurrentUser,
                                   applicationSupport: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask))
    }

    /// Probe known game folder names one level below the home directory. Do not
    /// enumerate protected folders, Library, app bundles, or hidden directories.
    static func commonLocations(home: URL, applicationSupport: [URL]) throws -> [URL] {
        var candidates = standardLocations(home: home, applicationSupport: applicationSupport)
        let excluded = Set(["Library", "Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies", "Applications", "Public"])
        let children = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for child in children.sorted(by: { $0.path < $1.path }).filter({ !excluded.contains($0.lastPathComponent) }).prefix(256) {
            try Task.checkCancellation()
            guard isDirectory(child), (try? child.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else { continue }
            // Only inspect these exact names, without listing the child's contents.
            candidates += [child.appendingPathComponent(".minecraft"), child.appendingPathComponent("minecraft")]
        }
        var result: [URL] = [], seen = Set<String>()
        for candidate in candidates {
            try Task.checkCancellation()
            guard isDirectory(candidate), isDirectory(candidate.appendingPathComponent("versions")) else { continue }
            let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
            if seen.insert(url.path).inserted { result.append(url) }
        }
        return result
    }

    private static func standardLocations(home: URL, applicationSupport: [URL]) -> [URL] {
        // HMCL's Metadata/OperatingSystem and XMCL's LauncherApp use
        // Application Support/minecraft on macOS. Also probe the conventional
        // dot-prefixed spelling for portable/migrated repositories. HMCL's
        // workspace-relative .minecraft has no fixed launcher-named home path.
        ([home] + applicationSupport).flatMap { root in ["minecraft", ".minecraft"].map { root.appendingPathComponent($0) } }
    }

    public static func inspect(_ selection: URL, existingNames: [String] = []) throws -> [MinecraftFolderPreview] {
        let selection = selection.standardizedFileURL
        guard isDirectory(selection) else { throw RuriError.message(Messages.FolderExperience.chooseFolder) }
        var roots: [URL] = []
        if isDirectory(selection.appendingPathComponent("versions")) || selection.lastPathComponent == "versions"
            || selection.deletingLastPathComponent().lastPathComponent == "versions"
            || FileManager.default.fileExists(atPath: selection.appendingPathComponent(GameDirectory.markerName).path) {
            roots = [selection]
        } else {
            let children = try FileManager.default.contentsOfDirectory(at: selection, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard children.count <= 2_000 else { throw RuriError.message(Messages.FolderExperience.chooseCloserFolder) }
            for child in children.sorted(by: { $0.path < $1.path }) where isDirectory(child) {
                try Task.checkCancellation()
                if isDirectory(child.appendingPathComponent("versions")) { roots.append(child) }
                else {
                    for name in [".minecraft", "minecraft"] {
                        let nested = child.appendingPathComponent(name)
                        if isDirectory(nested), isDirectory(nested.appendingPathComponent("versions")) { roots.append(nested) }
                    }
                }
            }
            if roots.isEmpty, children.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) { roots = [selection] }
        }
        guard !roots.isEmpty else { throw RuriError.message(Messages.FolderExperience.noFolderFound) }
        guard roots.count <= 32 else { throw RuriError.message(Messages.FolderExperience.chooseCloserFolder) }
        var previews: [MinecraftFolderPreview] = []
        for root in roots {
            try Task.checkCancellation()
            let catalog = try MinecraftDirectoryReader().scanNow(root, allowEmpty: true)
            guard !previews.contains(where: { $0.directory.path == catalog.directory.path }) else { continue }
            previews.append(.init(directory: catalog.directory, suggestedName: suggestedName(for: catalog.directory, existingNames: existingNames),
                                  versions: catalog.versions.map { .init(id: $0.id, subtitle: $0.subtitle, issue: $0.issue) }))
        }
        return previews
    }

    public static func suggestedName(for directory: URL, existingNames: [String]) -> String {
        let url = directory.standardizedFileURL.resolvingSymlinksInPath()
        let leaf = url.lastPathComponent
        let raw: String
        let manager = FileManager.default
        let standard = standardLocations(home: manager.homeDirectoryForCurrentUser,
                                         applicationSupport: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask))
        if standard.contains(where: { $0.standardizedFileURL.resolvingSymlinksInPath().path == url.path }) {
            raw = Messages.FolderExperience.localMinecraft.localized
        } else if [".minecraft", "minecraft"].contains(leaf.lowercased()) {
            raw = url.deletingLastPathComponent().lastPathComponent
        } else { raw = leaf }
        let cleaned = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String((cleaned.isEmpty ? Messages.FolderExperience.newFolder.localized : cleaned).prefix(90))
        var name = base, suffix = 2
        while existingNames.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            name = base + " (\(suffix))"; suffix += 1
        }
        return name
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }
}
