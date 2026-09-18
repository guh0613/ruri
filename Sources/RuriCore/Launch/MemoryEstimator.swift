import RuriLocalization
import Foundation

/// What one instance asks of the Java heap, gathered without opening any
/// archive. Only what the launcher manages counts: settings the player can
/// change inside the game, such as render distance, packs or shaders, are
/// covered by the comfort margin instead of steering the estimate.
public struct MemoryWorkload: Codable, Equatable, Sendable {
    public var gameVersion: String
    public var loader: LoaderKind
    /// Enabled mods only.
    public var modCount: Int
    public var modBytes: Int64
    /// False for the placeholder used where no instance folder was inspected.
    public var scanned: Bool
    public init(gameVersion: String, loader: LoaderKind, modCount: Int = 0, modBytes: Int64 = 0, scanned: Bool = true) {
        self.gameVersion = gameVersion; self.loader = loader; self.modCount = modCount; self.modBytes = modBytes; self.scanned = scanned
    }
    /// A current vanilla client with no content: used by previews that have no
    /// instance, such as the global defaults page.
    public static let generic = MemoryWorkload(gameVersion: "", loader: .vanilla, scanned: false)

    /// Inspect the instance's mods folder. A missing folder or unreadable
    /// entries count as nothing rather than failing: the estimate must always exist.
    public static func scan(paths: LauncherPaths, instance: GameInstance) -> MemoryWorkload {
        var result = MemoryWorkload(gameVersion: instance.gameVersion, loader: instance.loader)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let mods = paths.game(instance.id).appendingPathComponent("mods")
        if let entries = try? FileManager.default.contentsOfDirectory(at: mods, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
            for url in entries where !url.lastPathComponent.hasSuffix(".disabled") {
                guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                      ContentKind.mod.fileExtensions.contains(url.pathExtension.lowercased()) else { continue }
                result.modCount += 1; result.modBytes += Int64(values.fileSize ?? 0)
            }
        }
        return result
    }

    /// The last scan of this game folder while its mods folder is unchanged.
    /// Lists and detail pages redraw far more often than content changes, and
    /// a folder listing per redraw would add up.
    public static func cached(paths: LauncherPaths, instance: GameInstance) -> MemoryWorkload {
        let mods = paths.game(instance.id).appendingPathComponent("mods")
        let stamp = (try? mods.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSinceReferenceDate) ?? -1
        let fingerprint = MemoryWorkloadCache.Fingerprint(mods: mods.path, gameVersion: instance.gameVersion, loader: instance.loader, stamp: stamp)
        if let hit = MemoryWorkloadCache.shared.lookup(instance.id, fingerprint: fingerprint) { return hit }
        let result = scan(paths: paths, instance: instance)
        MemoryWorkloadCache.shared.store(result, for: instance.id, fingerprint: fingerprint)
        return result
    }
}

final class MemoryWorkloadCache: @unchecked Sendable {
    struct Fingerprint: Equatable { let mods: String; let gameVersion: String; let loader: LoaderKind; let stamp: Double }
    static let shared = MemoryWorkloadCache()
    private let lock = NSLock()
    private var entries: [UUID: (Fingerprint, MemoryWorkload)] = [:]
    func lookup(_ id: UUID, fingerprint: Fingerprint) -> MemoryWorkload? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[id], entry.0 == fingerprint else { return nil }
        return entry.1
    }
    func store(_ workload: MemoryWorkload, for id: UUID, fingerprint: Fingerprint) {
        lock.lock(); defer { lock.unlock() }
        entries[id] = (fingerprint, workload)
    }
}

/// The estimate and the reasoning behind it, frozen with the launch so session
/// records and diagnostics can show why the game got the heap it did.
public struct MemoryEstimate: Codable, Equatable, Sendable {
    public var workload: MemoryWorkload
    public var availability: MemoryAvailability
    /// The heap the content needs to run without constant collection.
    public var demandMB: Int
    /// Demand plus a comfort margin: fewer collections, room for chunk bursts,
    /// far render distances, packs and shaders chosen inside the game.
    public var generousMB: Int
    /// The most this machine should give a game right now.
    public var ceilingMB: Int
    public var maximumMB: Int
    public var initialMB: Int
    /// The machine could not cover even the basic demand.
    public var constrained: Bool { demandMB > maximumMB }
    /// Current free memory paid for the demand but not the full comfort margin.
    public var trimmed: Bool { !constrained && maximumMB < generousMB }
    /// One line naming the inputs: version, loader, mods and the memory the machine had free.
    public var basis: String {
        var parts = [workload.gameVersion.isEmpty ? "Minecraft" : "Minecraft \(workload.gameVersion)"]
        if workload.loader != .vanilla { parts.append(workload.loader.title) }
        parts.append(Messages.CoreMemoryEstimate.modCount(Int64(workload.modCount)).localized)
        if let available = availability.availableMB { parts.append(Messages.CoreMemoryEstimate.availableMemory(LaunchMemory.size(Int64(available) * 1_048_576)).localized) }
        return parts.joined(separator: " · ")
    }
}

/// Heap sizing for a Minecraft client. Too little means stutter and crashes;
/// too much means long garbage-collection pauses and a starved system. The
/// content sets a basic demand and a generous target; the machine's size caps
/// the heap and its free memory decides how far above the demand it goes.
public enum MemoryEstimator {
    /// Automatic heaps never exceed this; larger client heaps only lengthen GC pauses.
    public static let maximumAutomaticMB = 16384
    public static let minimumMB = 512

    public static func estimate(workload: MemoryWorkload, availability: MemoryAvailability) -> MemoryEstimate {
        let demand = roundUp(demandMB(workload))
        // Half again, up to 2 GB: the comfort margin is worth the most where the
        // demand is small, and past a few gigabytes extra heap mostly delays
        // collections that then take longer.
        let generous = min(maximumAutomaticMB, roundUp(demand + min(demand / 2, 2048)))
        let ceiling = max(minimumMB, roundDown(ceilingMB(availability)))
        let maximum = min(generous, ceiling)
        // Committing half the heap up front avoids the burst of young-generation
        // collections while a modded client loads. Pages stay untouched until
        // used, so the commitment costs no resident memory by itself.
        let initial = max(minimumMB, roundDown(maximum / 2))
        return .init(workload: workload, availability: availability, demandMB: demand, generousMB: generous, ceilingMB: ceiling, maximumMB: maximum, initialMB: min(initial, maximum))
    }

    /// Content demand in MB. Vanilla grows with each rewrite of the rendering
    /// and world code; loaders add their own bookkeeping; and mods add classes,
    /// registries and models with a falling marginal cost because large packs
    /// share libraries, while their size on disk hints at content-heavy mods.
    static func demandMB(_ workload: MemoryWorkload) -> Int {
        var total = baseMB(gameVersion: workload.gameVersion) + loaderMB(workload.loader) + modMB(count: workload.modCount)
        total += Int(min(1536, workload.modBytes / (4 * 1_048_576)))
        // Growth headroom: chunk loading and screen changes spike allocation
        // well above the steady state, and a heap at its limit collects constantly.
        return total + min(1024, total / 8)
    }

    static func baseMB(gameVersion: String) -> Int {
        guard let minor = minorVersion(gameVersion) else { return 2048 }
        switch minor { case ..<13: return 1024; case 13...16: return 1536; default: return 2048 }
    }

    static func loaderMB(_ loader: LoaderKind) -> Int {
        switch loader { case .forge, .neoforge: 512; case .fabric, .quilt, .legacyfabric: 256; case .liteloader, .optifine: 128; case .vanilla: 0 }
    }

    /// Roughly 20 MB per mod for small sets, falling to 6 MB in very large packs.
    static func modMB(count: Int) -> Int {
        var remaining = max(0, count), total = 0
        for (span, cost) in [(50, 20), (100, 15), (150, 10), (Int.max, 6)] {
            let taken = min(remaining, span); total += taken * cost; remaining -= taken
            if remaining == 0 { break }
        }
        return total
    }

    /// Leaves room for the JVM's own off-heap use, the graphics driver and the
    /// rest of the system. Free memory then decides how much of the comfort
    /// margin fits, but only lowers the ceiling to a point: free plus inactive
    /// pages understate what macOS will hand over, because it drops file
    /// caches and compresses idle apps when asked.
    static func ceilingMB(_ availability: MemoryAvailability) -> Int {
        let physical = availability.physicalMB
        var ceiling = physical <= 8192 ? physical / 2 : min(physical * 5 / 8, maximumAutomaticMB)
        if let available = availability.availableMB { ceiling = min(ceiling, max(available - 512, physical * 3 / 8)) }
        return ceiling
    }

    /// "1.20.1" and "1.21-pre1" give their minor number; snapshots and other
    /// names are treated as current.
    static func minorVersion(_ gameVersion: String) -> Int? {
        let parts = gameVersion.split(whereSeparator: { !$0.isNumber }).prefix(2)
        guard parts.count == 2, parts[0] == "1", let minor = Int(parts[1]) else { return nil }
        return minor
    }

    private static func roundUp(_ value: Int) -> Int { (value + 255) / 256 * 256 }
    private static func roundDown(_ value: Int) -> Int { value / 256 * 256 }
}
