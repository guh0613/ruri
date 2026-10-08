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

}
