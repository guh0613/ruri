import RuriLocalization
import Foundation
import Darwin

public struct MemorySettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case automatic, manual }
    public var mode: Mode
    public var maximumMB: Int
    public var initialMB: Int?
    public var metaspaceMB: Int?
    public init(mode: Mode = .manual, maximumMB: Int = 4096, initialMB: Int? = nil, metaspaceMB: Int? = nil) {
        self.mode = mode; self.maximumMB = maximumMB; self.initialMB = initialMB; self.metaspaceMB = metaspaceMB
    }
    /// Automatic mode sizes the heap from the instance's content and this
    /// machine; pass the scanned workload whenever an instance is known.
    public func resolve(availability: MemoryAvailability = .current(), workload: MemoryWorkload? = nil) throws -> LaunchMemory {
        guard (512...131_072).contains(maximumMB), initialMB == nil || (16...131_072).contains(initialMB!),
              metaspaceMB == nil || (16...131_072).contains(metaspaceMB!) else { throw RuriError.message(Messages.CoreMemorySettings.invalidMemoryLimits) }
        let maximum: Int, initial: Int
        var estimate: MemoryEstimate?
        if mode == .automatic {
            guard availability.physicalMB >= 512 else { throw RuriError.message(Messages.CoreMemorySettings.physicalMemoryUnreadable) }
            let estimated = MemoryEstimator.estimate(workload: workload ?? .generic, availability: availability)
            maximum = estimated.maximumMB; initial = initialMB ?? estimated.initialMB; estimate = estimated
        } else { maximum = maximumMB; initial = initialMB ?? min(512, maximum) }
        guard initial <= maximum else { throw RuriError.message(Messages.CoreMemorySettings.initialHeapTooLarge(String(describing: initial), String(describing: maximum))) }
        return .init(maximumBytes: Int64(maximum) * 1_048_576, minimumBytes: Int64(initial) * 1_048_576, initialBytes: Int64(initial) * 1_048_576,
                     metaspaceBytes: metaspaceMB.map { Int64($0) * 1_048_576 }, maximumSource: mode == .automatic ? .automatic : .settings,
                     initialSource: .settings, metaspaceSource: .settings, availability: mode == .automatic ? availability : nil, estimate: estimate)
    }
}

/// Evaluate heap flags in the order sent to Java. Keep the user's original
/// arguments: InitialHeapSize changes only the initial heap, whereas Xms also
/// changes the minimum, so rewriting aliases into Xms would change semantics.
public enum JVMHeapArguments {
    public static func resolve(base: LaunchMemory, arguments: [String]) throws -> LaunchMemory {
        var result = base
        for argument in arguments {
            if argument.hasPrefix("-Xmx") { result.maximumBytes = try bytes(String(argument.dropFirst(4))); result.maximumSource = .jvmArguments }
            else if argument.hasPrefix("-XX:MaxHeapSize=") { result.maximumBytes = try bytes(String(argument.dropFirst("-XX:MaxHeapSize=".count))); result.maximumSource = .jvmArguments }
            else if argument.hasPrefix("-Xms") {
                let value = try bytes(String(argument.dropFirst(4))); result.initialBytes = value; result.minimumBytes = value; result.initialSource = .jvmArguments
            } else if argument.hasPrefix("-XX:InitialHeapSize=") { result.initialBytes = try bytes(String(argument.dropFirst("-XX:InitialHeapSize=".count))); result.initialSource = .jvmArguments }
            else if argument.hasPrefix("-XX:MinHeapSize=") { result.minimumBytes = try bytes(String(argument.dropFirst("-XX:MinHeapSize=".count))) }
            else if argument.hasPrefix("-XX:MaxMetaspaceSize=") { result.metaspaceBytes = try bytes(String(argument.dropFirst("-XX:MaxMetaspaceSize=".count))); result.metaspaceSource = .jvmArguments }
        }
        // Zero initial/minimum heap requests JVM ergonomics, not a zero-byte
        // allocation. Preserve that choice without pretending to know its size.
        guard result.maximumBytes > 1_048_576, result.minimumBytes <= result.maximumBytes,
              result.initialBytes == 0 || (result.minimumBytes <= result.initialBytes && result.initialBytes <= result.maximumBytes) else {
            throw RuriError.message(Messages.CoreMemorySettings.heapSettingsMismatch)
        }
        return result
    }
    private static func bytes(_ text: String) throws -> Int64 {
        var digits = text, multiplier: Int64 = 1
        if let last = digits.last, let unit = ["k": Int64(1024), "m": Int64(1_048_576), "g": Int64(1_073_741_824)][String(last).lowercased()] {
            multiplier = unit; digits.removeLast()
        }
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int64(digits) else { throw RuriError.message(Messages.CoreMemorySettings.invalidMemorySize(String(describing: text))) }
        let (value, overflow) = number.multipliedReportingOverflow(by: multiplier)
        guard !overflow, value >= 0, value <= Int64.max - 1_048_575 else { throw RuriError.message(Messages.CoreMemorySettings.memorySizeOutOfRange) }
        return value
    }
}
