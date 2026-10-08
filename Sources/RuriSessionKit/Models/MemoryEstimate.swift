import Foundation
import RuriLocalization

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

}

public struct MemoryEstimate: Codable, Equatable, Sendable {
    package init(
        workload: MemoryWorkload, availability: MemoryAvailability, demandMB: Int, generousMB: Int, ceilingMB: Int, maximumMB: Int,
        initialMB: Int
    ) {
        self.workload = workload
        self.availability = availability
        self.demandMB = demandMB
        self.generousMB = generousMB
        self.ceilingMB = ceilingMB
        self.maximumMB = maximumMB
        self.initialMB = initialMB
    }

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
