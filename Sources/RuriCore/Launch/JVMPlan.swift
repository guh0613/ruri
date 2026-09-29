import Foundation

/// The heap, collector and options of one launch, decided in one place. The
/// launch, the memory estimate and the tuning preview all read this, so the
/// heap the settings show is the heap the game gets.
public struct JVMPlan: Equatable, Sendable {
    /// The heap flags Ruri passes, raised for ZGC when the rules did so. The
    /// game's and the user's own flags follow them on the command line.
    public var base: LaunchMemory
    /// The heap the game ends up with once every flag applies.
    public var memory: LaunchMemory
    public var tuning: JVMTuning

    /// `launchArguments` are the game's own JVM arguments and Ruri's fixed ones;
    /// `userArguments` come last and win.
    public static func make(base: LaunchMemory, mode: JVMTuningMode, java: JavaRuntime?, capabilities: JavaCapabilities?, workload: MemoryWorkload,
                            availability: MemoryAvailability, launchArguments: [String] = [], userArguments: [String]) throws -> JVMPlan {
        let others = launchArguments + userArguments
        let requested = try JVMHeapArguments.resolve(base: base, arguments: others)
        let tuning = JVMTuning.resolve(.init(mode: mode, javaMajor: java?.major ?? 0, capabilities: capabilities, memory: requested,
                                             workload: workload, availability: availability, arguments: others))
        let tuned = tuning.applying(to: base)
        return .init(base: tuned, memory: try JVMHeapArguments.resolve(base: tuned, arguments: others), tuning: tuning)
    }

    /// The plan settings pages and summaries show for these settings on this
    /// machine now. Without a context no collector is chosen yet, so the heap
    /// is the estimate alone.
    public static func preview(settings: LaunchSettingsValues, workload: MemoryWorkload?, context: JVMRuntimeContext?, availability: MemoryAvailability = .current()) throws -> JVMPlan {
        try make(base: settings.memory.resolve(availability: availability, workload: workload), mode: settings.jvmTuning, java: context?.java,
                 capabilities: context?.capabilities, workload: workload ?? .generic, availability: availability, userArguments: ArgumentTokenizer.split(settings.jvmArguments))
    }
}

/// The Java a launch of this instance would pick and the flags it accepts,
/// looked up ahead of time for settings previews.
public struct JVMRuntimeContext: Equatable, Sendable {
    /// Nil when no installed runtime fits; the launch would install one.
    public var java: JavaRuntime?
    public var capabilities: JavaCapabilities?
    public init(java: JavaRuntime? = nil, capabilities: JavaCapabilities? = nil) { self.java = java; self.capabilities = capabilities }

    public static func preview(instance: GameInstance, java selection: JavaSelection, paths: LauncherPaths, runtimes: [JavaRuntime]) async -> JVMRuntimeContext {
        var selected = instance; selected.javaPath = selection.path; selected.javaMajor = selection.major
        guard let manifest = await PreviewManifestCache.shared.manifest(paths: paths, instance: instance),
              let requirement = try? GameJavaRequirement(instance: selected, manifest: manifest),
              let java = try? requirement.select(from: runtimes) else { return .init() }
        return .init(java: java, capabilities: await JavaCapabilities.load(for: java, cache: paths.cache))
    }
}

/// Resolved manifests for previews, reused while none of their source files
/// changed, in memory and in the launcher's cache folder. A version in a
/// shared Minecraft folder takes a directory scan and an inheritance merge,
/// near a second for large modpacks. Launches still read and validate the
/// manifest in full.
final class PreviewManifestCache: @unchecked Sendable {
    private struct Stored: Codable { let fingerprint: [String]; let manifest: VersionManifest }
    static let shared = PreviewManifestCache()
    private let lock = NSLock()
    private var entries: [UUID: ([String], VersionManifest)] = [:]

    func manifest(paths: LauncherPaths, instance: GameInstance) async -> VersionManifest? {
        let file = paths.cache.appendingPathComponent("preview-manifests/\(instance.id.uuidString).json")
        let (fingerprint, stored) = await Task.detached(priority: .userInitiated) { () -> ([String]?, Stored?) in
            (Self.fingerprint(paths: paths, instance: instance), try? JSONDecoder().decode(Stored.self, from: Data(contentsOf: file)))
        }.value
        guard let fingerprint else { return try? await GameInstaller(paths: paths).loadManifest(instance) }
        if let hit = lookup(instance.id, fingerprint) { return hit }
        if let stored, stored.fingerprint == fingerprint { store(stored.manifest, fingerprint, for: instance.id); return stored.manifest }
        guard let manifest = try? await GameInstaller(paths: paths).loadManifest(instance) else { return nil }
        store(manifest, fingerprint, for: instance.id)
        let record = Stored(fingerprint: fingerprint, manifest: manifest)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(record).write(to: file, options: .atomic)
        }
        return manifest
    }

    /// Every file the manifest can be read from, with its size and date: the
    /// instance's own manifest, or each version document of the shared folder,
    /// since any of them can be a parent in the inheritance chain.
    static func fingerprint(paths: LauncherPaths, instance: GameInstance) -> [String]? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        func stamp(_ url: URL) -> String {
            let values = try? url.resourceValues(forKeys: keys)
            return "\(url.path)|\(values?.fileSize ?? -1)|\(values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1)"
        }
        var result = [instance.repositoryVersionID ?? "", instance.gameVersion, instance.loader.rawValue]
        guard instance.repositoryVersionID != nil else { return result + [stamp(paths.manifest(instance.id))] }
        let versions = paths.directoryRoot(paths.directoryID(for: instance.id)).appendingPathComponent("versions")
        guard let children = try? FileManager.default.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil) else { return nil }
        for child in children.sorted(by: { $0.path < $1.path }) {
            let files = (try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: Array(keys))) ?? []
            result += files.filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.path < $1.path }.map(stamp)
        }
        return result
    }

    private func lookup(_ id: UUID, _ fingerprint: [String]) -> VersionManifest? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[id], entry.0 == fingerprint else { return nil }
        return entry.1
    }
    private func store(_ manifest: VersionManifest, _ fingerprint: [String], for id: UUID) {
        lock.lock(); defer { lock.unlock() }
        entries[id] = (fingerprint, manifest)
    }
}
