import RuriLocalization
import Foundation

public struct JavaLocation: Codable, Equatable, Sendable {
    public let path: String
    public let addedRuntime: JavaRuntime
    public init(path: String, addedRuntime: JavaRuntime) { self.path = path; self.addedRuntime = addedRuntime }
}
public struct JavaRuntimeEntry: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let runtime: JavaRuntime?
    public let issue: String?
    public let manual: Bool
    public let configured: Bool
    public let addedRuntime: JavaRuntime?
    public let managedID: String?
    public let remote: RemoteJava?
    public var source: String { managedID != nil ? Messages.CoreJavaRuntimeStore.sourceText1.localized : manual ? Messages.CoreJavaRuntimeStore.sourceText2.localized : configured ? Messages.CoreJavaRuntimeStore.sourceText3.localized : Messages.CoreJavaRuntimeStore.sourceText4.localized }
}
public struct JavaRemovalResult: Sendable {
    public let state: PersistentState
    public let trashedURL: URL?
}

public enum JavaRuntimeStore {
    public static func add(_ selection: URL, replacing oldPath: String? = nil, paths: LauncherPaths) async throws -> PersistentState {
        let runtime = try await Task.detached(priority: .userInitiated) {
            try JavaDiscovery.inspect(JavaDiscovery.executable(in: selection).path)
        }.value
        return try StateStore.update(paths) { state in
            var locations = state.settings.javaLocations ?? []
            locations.removeAll { JavaDiscovery.sameExecutable($0.path, runtime.path) || $0.path == oldPath }
            locations.append(.init(path: runtime.path, addedRuntime: runtime))
            state.settings.javaLocations = locations
            if let oldPath { replaceReferences(in: &state, matching: { JavaDiscovery.sameExecutable($0, oldPath) }, with: runtime.path) }
        }
    }
    public static func forget(_ path: String, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { $0.settings.javaLocations?.removeAll { $0.path == path } }
    }
    public static func useByDefault(_ path: String, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { $0.settings.defaultJava = .path(path) }
    }
    static func validate(_ locations: [JavaLocation]) throws {
        guard locations.count <= 256, Set(locations.map(\.path)).count == locations.count,
              locations.allSatisfy({ $0.path.hasPrefix("/") && $0.path.utf8.count <= 8192 && !$0.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else {
            throw RuriError.message(Messages.CoreJavaRuntimeStore.validateText1)
        }
    }
    static func directory(_ id: String, paths: LauncherPaths, partial: Bool = false) throws -> URL {
        guard !id.isEmpty, id.utf8.count <= 240, !id.hasPrefix("."), !id.contains("/"), !id.contains("\\"), !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuriError.message(Messages.CoreJavaRuntimeStore.directoryText1) }
        let raw = paths.runtimes.appendingPathComponent((partial ? ".partial-" : "") + id)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: raw.path)) == nil else { throw RuriError.message(Messages.CoreJavaRuntimeStore.rawText1) }
        return try LauncherPaths.safePath((partial ? ".partial-" : "") + id, within: paths.runtimes)
    }
    private static func contains(_ path: String, directory: URL) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(directory.standardizedFileURL.resolvingSymlinksInPath().path + "/")
    }
    public static func references(to id: String, paths: LauncherPaths, partial: Bool = false) throws -> [String] {
        let root = try directory(id, paths: paths, partial: partial), state = try StateStore.load(paths)
        return references(in: state, directory: root)
    }
    private static func references(in state: PersistentState, directory: URL) -> [String] {
        var result: [String] = []
        if let path = state.settings.defaultLaunchSettings.java.path, contains(path, directory: directory) { result.append(Messages.CoreJavaRuntimeStore.pathText1.localized) }
        for instance in state.instances + (state.detachedMinecraftFolders ?? []).flatMap(\.instances) {
            if let path = instance.resolvedLaunchSettings(defaults: state.settings).java.path, contains(path, directory: directory) { result.append(instance.name) }
        }
        return result
    }
    public static func trash(_ id: String, paths: LauncherPaths, resetReferences: Bool = false, partial: Bool = false) throws -> JavaRemovalResult {
        let root = try directory(id, paths: paths, partial: partial)
        guard FileManager.default.fileExists(atPath: root.path) else { throw RuriError.message(Messages.CoreJavaRuntimeStore.rootText1) }
        let lease = try JavaRuntimeLease.acquire(id: id, paths: paths, exclusive: true)
        defer { withExtendedLifetime(lease) {} }
        try JavaRuntimeLease.requireNoRunningProcess(in: root)
        if try StateStore.load(paths).schemaVersion < 17 { try StateStore.update(paths) { _ in } }
        var trashed: NSURL?
        do {
            let saved = try StateStore.update(paths) { state in
                let references = references(in: state, directory: root)
                guard references.isEmpty || resetReferences else { throw RuriError.message(Messages.CoreJavaRuntimeStore.referencesText1(String(describing: references.joined(separator: "、")))) }
                if resetReferences { replaceReferences(in: &state, matching: { contains($0, directory: root) }, with: nil) }
                state.settings.javaLocations?.removeAll { contains($0.path, directory: root) }
                try FileManager.default.trashItem(at: root, resultingItemURL: &trashed)
            }
            return .init(state: saved, trashedURL: trashed.map { $0 as URL })
        } catch {
            if let trashed {
                do { try FileManager.default.moveItem(at: trashed as URL, to: root) }
                catch { throw RuriError.message(Messages.CoreJavaRuntimeStore.trashedText1) }
            }
            throw error
        }
    }
    private static func replaceReferences(in state: inout PersistentState, matching: (String) -> Bool, with replacement: String?) {
        let value: JavaSelection = replacement.map(JavaSelection.path) ?? .automatic
        if let path = state.settings.defaultLaunchSettings.java.path, matching(path) { state.settings.defaultJava = value }
        func update(_ instance: inout GameInstance) {
            if let path = instance.javaPath, matching(path) { instance.javaPath = replacement }
            if let path = instance.launchOverrides?.java?.path, matching(path) { instance.launchOverrides?.java = value }
        }
        for index in state.instances.indices { update(&state.instances[index]) }
        if var detached = state.detachedMinecraftFolders {
            for folder in detached.indices { for index in detached[folder].instances.indices { update(&detached[folder].instances[index]) } }
            state.detachedMinecraftFolders = detached
        }
    }
    public static func descriptor(_ id: String, paths: LauncherPaths) -> RemoteJava? {
        guard (try? directory(id, paths: paths)) != nil else { return nil }
        for file in [paths.runtimes.appendingPathComponent(id + "/.ruri-runtime.json"), paths.cache.appendingPathComponent("java-runtime-descriptors/" + id + ".json")] {
            if let data = try? RunDirectoryCopyGuard.read(file, limit: 64 * 1024), let remote = try? JSONDecoder().decode(RemoteJava.self, from: data), remote.id == id { return remote }
        }
        // Older installs retained the original Mojang file manifest. It can
        // repair that exact release even when the catalog now lists a newer one.
        let file = paths.cache.appendingPathComponent("java-" + id + ".json")
        guard let data = try? RunDirectoryCopyGuard.read(file, limit: 32 * 1024 * 1024),
              (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["files"] != nil else { return nil }
        for arch in ["aarch64", "x86_64"] {
            if let range = id.range(of: "-" + arch + "-"), let hash = try? InstanceTransfer.sha1(file) {
                return .init(component: String(id[..<range.lowerBound]), architecture: arch, version: String(id[range.upperBound...]), manifest: .init(url: nil, sha1: hash, size: Int64(data.count)))
            }
        }
        return nil
    }
}

extension JavaDiscovery {
    public static func inventory(paths: LauncherPaths, extra: [String] = []) async -> [JavaRuntimeEntry] {
        await Task.detached(priority: .utility) {
            let state = (try? StateStore.load(paths)) ?? .init(), fm = FileManager.default
            let manual = state.settings.javaLocations ?? []
            let configured = state.instances.compactMap { $0.resolvedLaunchSettings(defaults: state.settings).java.path } + [state.settings.defaultLaunchSettings.java.path].compactMap { $0 } + extra
            var candidates = manual.map(\.path) + configured
            for child in (try? fm.contentsOfDirectory(at: paths.runtimes, includingPropertiesForKeys: nil)) ?? [] where !child.lastPathComponent.hasPrefix(".") {
                candidates.append(child.appendingPathComponent("jre.bundle/Contents/Home/bin/java").path)
            }
            let home = fm.homeDirectoryForCurrentUser
            let folders = [URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines"), home.appendingPathComponent("Library/Java/JavaVirtualMachines"),
                           URL(fileURLWithPath: "/opt/homebrew/opt"), URL(fileURLWithPath: "/usr/local/opt")]
            for folder in folders {
                for child in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where !child.lastPathComponent.hasPrefix(".") {
                    if folder.path.hasSuffix("/opt"), !child.lastPathComponent.contains("openjdk") { continue }
                    if let binary = try? executable(in: child) { candidates.append(binary.resolvingSymlinksInPath().path) }
                }
            }
            if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] { candidates.append(URL(fileURLWithPath: javaHome).appendingPathComponent("bin/java").path) }
            var seen = Set<String>(), result: [JavaRuntimeEntry] = []
            for path in candidates {
                if Task.isCancelled { break }
                let key = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
                guard seen.insert(key).inserted else { continue }
                let known = manual.first { sameExecutable($0.path, path) }
                let id = JavaRuntimeLease.managedID(binary: URL(fileURLWithPath: path), paths: paths)
                let remote = id.flatMap { JavaRuntimeStore.descriptor($0, paths: paths) }
                let selected = configured.contains { sameExecutable($0, path) }
                do { result.append(.init(path: path, runtime: try inspect(path), issue: nil, manual: known != nil, configured: selected, addedRuntime: known?.addedRuntime, managedID: id, remote: remote)) }
                catch { result.append(.init(path: path, runtime: nil, issue: error.localizedDescription, manual: known != nil, configured: selected, addedRuntime: known?.addedRuntime, managedID: id, remote: remote)) }
            }
            return result.sorted { first, second in
                guard let a = first.runtime, let b = second.runtime else { return first.runtime != nil && second.runtime == nil }
                if a.isNative != b.isNative { return a.isNative }
                if a.major != b.major { return a.major > b.major }
                return a.version.compare(b.version, options: .numeric) == .orderedDescending
            }
        }.value
    }
}
