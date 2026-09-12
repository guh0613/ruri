import RuriLocalization
import Foundation
import Darwin

public struct MemoryAvailability: Equatable, Sendable {
    public let physicalMB: Int
    public let availableMB: Int?
    public init(physicalMB: Int, availableMB: Int? = nil) { self.physicalMB = physicalMB; self.availableMB = availableMB }
    public static func current() -> Self {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self(); defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        let pageSize = sysconf(_SC_PAGESIZE)
        // Inactive pages are reclaimable, not a guarantee of immediately free
        // RAM. Purgeable/speculative pages are subsets and are not added twice.
        let available = status == KERN_SUCCESS && pageSize > 0 ? Int((UInt64(info.free_count) + UInt64(info.inactive_count)) * UInt64(pageSize) / 1_048_576) : nil
        return .init(physicalMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576), availableMB: available)
    }
}

public struct MemorySettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case automatic, manual }
    public var mode: Mode
    public var maximumMB: Int
    public var initialMB: Int?
    public var metaspaceMB: Int?
    public init(mode: Mode = .manual, maximumMB: Int = 4096, initialMB: Int? = nil, metaspaceMB: Int? = nil) {
        self.mode = mode; self.maximumMB = maximumMB; self.initialMB = initialMB; self.metaspaceMB = metaspaceMB
    }
    public func resolve(availability: MemoryAvailability = .current()) throws -> LaunchMemory {
        guard (512...131_072).contains(maximumMB), initialMB == nil || (16...131_072).contains(initialMB!),
              metaspaceMB == nil || (16...131_072).contains(metaspaceMB!) else { throw RuriError.message(Messages.CoreMemorySettings.resolveText1) }
        let maximum: Int
        if mode == .automatic {
            guard availability.physicalMB >= 512 else { throw RuriError.message(Messages.CoreMemorySettings.maximumText1) }
            var candidate = min(8192, availability.physicalMB / 4)
            if let available = availability.availableMB { candidate = min(candidate, max(0, available) / 2) }
            maximum = max(512, candidate / 256 * 256)
        } else { maximum = maximumMB }
        let initial = initialMB ?? min(512, maximum)
        guard initial <= maximum else { throw RuriError.message(Messages.CoreMemorySettings.initialText1(String(describing: initial), String(describing: maximum))) }
        return .init(maximumBytes: Int64(maximum) * 1_048_576, minimumBytes: Int64(initial) * 1_048_576, initialBytes: Int64(initial) * 1_048_576,
                     metaspaceBytes: metaspaceMB.map { Int64($0) * 1_048_576 }, maximumSource: mode == .automatic ? .automatic : .settings,
                     initialSource: .settings, metaspaceSource: .settings, availability: mode == .automatic ? availability : nil)
    }
}

public struct LaunchMemory: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case automatic, settings, jvmArguments
        public var title: String { switch self { case .automatic: Messages.CoreMemorySettings.titleText1.localized; case .settings: Messages.CoreMemorySettings.titleText2.localized; case .jvmArguments: Messages.CoreMemorySettings.titleText3.localized } }
    }
    public var maximumBytes: Int64
    public var minimumBytes: Int64
    public var initialBytes: Int64
    public var metaspaceBytes: Int64?
    public var maximumSource: Source
    public var initialSource: Source
    public var metaspaceSource: Source
    public var availability: MemoryAvailability?
    public var maximumMB: Int { Int((maximumBytes + 1_048_575) / 1_048_576) }
    public var summary: String { Messages.CoreMemorySettings.summaryText2(String(describing: Self.size(maximumBytes)), String(describing: initialBytes == 0 ? Messages.CoreMemorySettings.summaryText1.localized : Self.size(initialBytes)), String(describing: maximumSource.title)).localized + (metaspaceBytes.map { " · Metaspace ≤ \(Self.size($0))" } ?? "") }
    public var arguments: [String] {
        func size(_ value: Int64) -> String { value % 1_048_576 == 0 ? "\(value / 1_048_576)M" : String(value) }
        var values = ["-Xms\(size(minimumBytes))", "-Xmx\(size(maximumBytes))"]
        if initialBytes != minimumBytes { values.append("-XX:InitialHeapSize=\(size(initialBytes))") }
        if let metaspaceBytes { values.append("-XX:MaxMetaspaceSize=\(size(metaspaceBytes))") }
        return values
    }
    public static func size(_ bytes: Int64) -> String {
        if bytes % 1_048_576 == 0 { return "\(bytes / 1_048_576) MB" }
        return LocalizedFormat.bytes(bytes, memory: true)
    }
}

extension MemoryAvailability: Codable {}

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
            throw RuriError.message(Messages.CoreMemorySettings.valueText1)
        }
        return result
    }
    private static func bytes(_ text: String) throws -> Int64 {
        var digits = text, multiplier: Int64 = 1
        if let last = digits.last, let unit = ["k": Int64(1024), "m": Int64(1_048_576), "g": Int64(1_073_741_824)][String(last).lowercased()] {
            multiplier = unit; digits.removeLast()
        }
        guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int64(digits) else { throw RuriError.message(Messages.CoreMemorySettings.numberText1(String(describing: text))) }
        let (value, overflow) = number.multipliedReportingOverflow(by: multiplier)
        guard !overflow, value >= 0, value <= Int64.max - 1_048_575 else { throw RuriError.message(Messages.CoreMemorySettings.numberText2) }
        return value
    }
}
