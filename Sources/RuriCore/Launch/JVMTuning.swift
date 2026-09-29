import RuriLocalization
import Foundation

/// How far Ruri goes beyond the JVM arguments the game itself asks for.
public enum JVMTuningMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Compatibility and diagnostic options plus a collector chosen for the
    /// content, the machine and the Java that runs it.
    case recommended
    /// Recommended, plus newer JVM features with less mileage behind them.
    case experimental
    /// Only the game's own arguments and the user's.
    case off
    public var id: String { rawValue }
    public var title: String {
        switch self { case .recommended: Messages.CoreJVMTuning.recommended.localized; case .experimental: Messages.CoreJVMTuning.experimental.localized; case .off: Messages.CoreJVMTuning.off.localized }
    }
}

/// Everything the rules look at. The arguments are all other JVM arguments of
/// the launch, the game's and the user's, so nothing already set is repeated.
public struct JVMTuningContext: Sendable {
    public var mode: JVMTuningMode
    public var javaMajor: Int
    /// Nil when the runtime could not be probed: only options that no JVM
    /// can refuse are added then.
    public var capabilities: JavaCapabilities?
    /// The heap after the user's own heap flags.
    public var memory: LaunchMemory
    public var workload: MemoryWorkload
    public var availability: MemoryAvailability
    public var arguments: [String]
    public init(mode: JVMTuningMode, javaMajor: Int, capabilities: JavaCapabilities?, memory: LaunchMemory, workload: MemoryWorkload, availability: MemoryAvailability, arguments: [String]) {
        self.mode = mode; self.javaMajor = javaMajor; self.capabilities = capabilities; self.memory = memory
        self.workload = workload; self.availability = availability; self.arguments = arguments
    }
}

/// The options added to one launch and the reason for each, frozen with the
/// session so history and diagnostics can show what the game ran with.
public struct JVMTuning: Codable, Equatable, Sendable {
    public enum Collector: String, Codable, Sendable {
        case g1, z
        public var title: String { switch self { case .g1: "G1"; case .z: "ZGC" } }
    }
    public enum Reason: String, Codable, Sendable {
        case diagnostics, systemProxy, legacyForge, unsafeMemoryAccess, g1, zgc, compactHeaders
        public var title: String {
            switch self {
            case .diagnostics: Messages.CoreJVMTuning.diagnostics.localized
            case .systemProxy: Messages.CoreJVMTuning.systemProxy.localized
            case .legacyForge: Messages.CoreJVMTuning.legacyForge.localized
            case .unsafeMemoryAccess: Messages.CoreJVMTuning.unsafeMemoryAccess.localized
            case .g1: Messages.CoreJVMTuning.g1.localized
            case .zgc: Messages.CoreJVMTuning.zgc.localized
            case .compactHeaders: Messages.CoreJVMTuning.compactHeaders.localized
            }
        }
    }
    /// A step the rules would otherwise have taken, and why it was not.
    public enum Note: String, Codable, Sendable {
        case disabled, capabilitiesUnknown, collectorChosenByUser, zgcHeadroom
        public var title: String {
            switch self {
            case .disabled: Messages.CoreJVMTuning.disabled.localized
            case .capabilitiesUnknown: Messages.CoreJVMTuning.capabilitiesUnknown.localized
            case .collectorChosenByUser: Messages.CoreJVMTuning.collectorChosenByUser.localized
            case .zgcHeadroom: Messages.CoreJVMTuning.zgcHeadroom.localized
            }
        }
    }
    public struct Argument: Codable, Equatable, Sendable {
        public var value: String
        public var reason: Reason
        public init(_ value: String, _ reason: Reason) { self.value = value; self.reason = reason }
    }
    public var mode: JVMTuningMode
    public var collector: Collector?
    public var arguments: [Argument]
    public var notes: [Note]
    /// The automatic heap before it was raised for ZGC.
    public var heapRaisedFromMB: Int?
    /// The automatic heap after it was raised for ZGC.
    public var heapRaisedToMB: Int?
    public init(mode: JVMTuningMode, collector: Collector? = nil, arguments: [Argument] = [], notes: [Note] = []) {
        self.mode = mode; self.collector = collector; self.arguments = arguments; self.notes = notes
    }
    public var values: [String] { arguments.map(\.value) }

    /// One line per reason with its options, then what was left out.
    public var detail: String {
        var lines: [String] = []
        for reason in arguments.map(\.reason).reduce(into: [Reason](), { if !$0.contains($1) { $0.append($1) } }) {
            lines.append(reason.title + ": " + arguments.filter { $0.reason == reason }.map(\.value).joined(separator: " "))
        }
        if let from = heapRaisedFromMB, let to = heapRaisedToMB {
            lines.append(Messages.CoreJVMTuning.heapRaised(LaunchMemory.size(Int64(from) * 1_048_576), LaunchMemory.size(Int64(to) * 1_048_576)).localized)
        }
        lines += notes.map(\.title)
        return lines.joined(separator: "\n")
    }

    /// The heap the launch actually passes: raised for ZGC when the rules did so.
    public func applying(to memory: LaunchMemory) -> LaunchMemory {
        guard let to = heapRaisedToMB else { return memory }
        var result = memory; result.maximumBytes = Int64(to) * 1_048_576
        return result
    }

    // Generational ZGC keeps pauses far below a frame at any heap size, but it
    // stores references uncompressed and wants room to collect while the game
    // keeps allocating. It pays off where G1's pauses grow: large heaps filled
    // by many mods, on machines that can spare the extra memory.
    static let zgcMinimumHeapMB = 6144
    static let zgcMinimumMods = 50
    static let zgcMinimumPhysicalMB = 16384
    /// Extra automatic heap for ZGC, in percent of the estimate.
    static let zgcHeadroomPercent = 20

    public static func resolve(_ context: JVMTuningContext) -> JVMTuning {
        var result = JVMTuning(mode: context.mode)
        guard context.mode != .off else { result.notes = [.disabled]; return result }
        let existing = Set(context.arguments.compactMap(optionKey))
        func add(_ value: String, _ reason: Reason) {
            guard let key = optionKey(value), !existing.contains(key), !result.arguments.contains(where: { optionKey($0.value) == key }) else { return }
            result.arguments.append(.init(value, reason))
        }
        let capabilities = context.capabilities
        // Only flags the runtime listed; experimental ones are unlocked below.
        func flag(_ name: String, _ setting: String, _ reason: Reason) {
            guard capabilities?.kind(name) != nil else { return }
            add("-XX:" + (setting == "+" || setting == "-" ? setting + name : name + "=" + setting), reason)
        }

        flag("OmitStackTraceInFastThrow", "-", .diagnostics)
        let proxyPrefixes = ["-Djava.net.useSystemProxies=", "-Dhttp.proxy", "-Dhttps.proxy", "-DsocksProxy", "-Djava.net.socks."]
        if !context.arguments.contains(where: { argument in proxyPrefixes.contains { argument.hasPrefix($0) } }) {
            add("-Djava.net.useSystemProxies=true", .systemProxy)
        }
        // Forge for 1.12 and older checks the signature of the Minecraft jar
        // and binary patches, which fails on repackaged or patched clients.
        if context.workload.loader == .forge, let minor = MemoryEstimator.minorVersion(context.workload.gameVersion), minor <= 12 {
            add("-Dfml.ignoreInvalidMinecraftCertificates=true", .legacyForge)
            add("-Dfml.ignorePatchDiscrepancies=true", .legacyForge)
        }
        // Java 24 warns once old code touches these methods, and later
        // releases refuse them by default; mods cannot move off them overnight.
        if context.javaMajor >= 24, capabilities?.unsafeMemoryAccessOption == true {
            add("--sun-misc-unsafe-memory-access=allow", .unsafeMemoryAccess)
        }

        if let capabilities {
            if context.arguments.contains(where: isCollectorChoice) { result.notes.append(.collectorChosenByUser) }
            else {
                let choice = chooseCollector(context, capabilities: capabilities)
                result.collector = choice.collector
                for (name, setting) in choice.flags { flag(name, setting, choice.collector == .z ? .zgc : .g1) }
                if let note = choice.note { result.notes.append(note) }
                if let raised = choice.raisedHeapMB { result.heapRaisedFromMB = context.memory.maximumMB; result.heapRaisedToMB = raised }
            }
            if context.mode == .experimental, capabilities.kind("UseCompactObjectHeaders") == .product {
                flag("UseCompactObjectHeaders", "+", .compactHeaders)
            }
        } else { result.notes.append(.capabilitiesUnknown) }

        if let first = result.arguments.first(where: { capabilities?.kind(flagName($0.value) ?? "") == .experimental }),
           !context.arguments.contains("-XX:+UnlockExperimentalVMOptions") {
            result.arguments.insert(.init("-XX:+UnlockExperimentalVMOptions", first.reason), at: 0)
        }
        return result
    }

    private struct CollectorChoice {
        var collector: Collector?
        /// Flag names with "+", "-" or a value.
        var flags: [(String, String)] = []
        var note: Note?
        var raisedHeapMB: Int?
    }

    private static func chooseCollector(_ context: JVMTuningContext, capabilities: JavaCapabilities) -> CollectorChoice {
        var choice = CollectorChoice()
        let heapMB = context.memory.maximumMB
        // Java 23 made ZGC generational by default and 24 removed the rest;
        // 21 and 22 ask for it with ZGenerational. Java 17's ZGC is single-generation.
        let generational = capabilities.kind("UseZGC") != nil && (context.javaMajor >= 23 || capabilities.kind("ZGenerational") != nil)
        if generational, heapMB >= zgcMinimumHeapMB, context.workload.modCount >= zgcMinimumMods, context.availability.physicalMB >= zgcMinimumPhysicalMB {
            // An automatic heap grows to cover what ZGC costs; a heap the user
            // chose stays as chosen. If the machine cannot spare the growth, G1
            // on the estimated heap is the better trade.
            var fits = context.memory.maximumSource != .automatic
            if context.memory.maximumSource == .automatic, let estimate = context.memory.estimate {
                let target = min(MemoryEstimator.maximumAutomaticMB, (heapMB * (100 + zgcHeadroomPercent) / 100 + 255) / 256 * 256)
                fits = target <= estimate.ceilingMB
                if fits && target > heapMB { choice.raisedHeapMB = target }
            }
            if fits {
                choice.collector = .z
                choice.flags = [("UseZGC", "+")] + (context.javaMajor < 23 ? [("ZGenerational", "+")] : [])
                return choice
            }
            choice.note = .zgcHeadroom
        }
        guard capabilities.kind("UseG1GC") != nil else { return choice }
        // The collector and pause goal of Minecraft's own launcher. Regions of
        // 8 to 32 MB keep a few hundred or more of them while letting the large
        // arrays chunk data uses stay out of humongous allocation.
        choice.collector = .g1
        choice.flags = [("UseG1GC", "+"), ("G1NewSizePercent", "20"), ("G1ReservePercent", "20"), ("MaxGCPauseMillis", "50"),
                        ("G1HeapRegionSize", heapMB <= 4096 ? "8M" : heapMB <= 8192 ? "16M" : "32M")]
        return choice
    }

    /// `-XX:+UseZGC`, `-XX:-UseG1GC`, `-XX:+UseShenandoahGC` and the like: the
    /// user picked the collector, so none of the collector options apply.
    public static func isCollectorChoice(_ argument: String) -> Bool {
        guard let name = flagName(argument), argument.hasPrefix("-XX:+") || argument.hasPrefix("-XX:-") else { return false }
        return name.hasPrefix("Use") && name.hasSuffix("GC")
    }
    static func flagName(_ argument: String) -> String? {
        guard argument.hasPrefix("-XX:") else { return nil }
        var name = argument.dropFirst(4)
        if name.first == "+" || name.first == "-" { name = name.dropFirst() }
        return String(name.prefix { $0 != "=" })
    }
    /// What two arguments must share to set the same thing: a flag's name, a
    /// property's name or a launcher option's name, whatever their values.
    static func optionKey(_ argument: String) -> String? {
        if let name = flagName(argument) { return "XX:" + name }
        if argument.hasPrefix("-D") { return "D:" + argument.dropFirst(2).prefix { $0 != "=" } }
        if argument.hasPrefix("--") { return String(argument.prefix { $0 != "=" }) }
        return nil
    }
}
