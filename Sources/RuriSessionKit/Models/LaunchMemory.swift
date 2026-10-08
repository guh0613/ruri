import Darwin
import Foundation
import RuriLocalization

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

public struct LaunchMemory: Codable, Equatable, Sendable {
    package init(maximumBytes: Int64, minimumBytes: Int64, initialBytes: Int64, metaspaceBytes: Int64? = nil, maximumSource: Source, initialSource: Source, metaspaceSource: Source, availability: MemoryAvailability? = nil, estimate: MemoryEstimate? = nil) {
        self.maximumBytes = maximumBytes
        self.minimumBytes = minimumBytes
        self.initialBytes = initialBytes
        self.metaspaceBytes = metaspaceBytes
        self.maximumSource = maximumSource
        self.initialSource = initialSource
        self.metaspaceSource = metaspaceSource
        self.availability = availability
        self.estimate = estimate
    }

    public enum Source: String, Codable, Sendable {
        case automatic, settings, jvmArguments
        public var title: String { switch self { case .automatic: Messages.CoreMemorySettings.automaticEstimation.localized; case .settings: Messages.CoreMemorySettings.memorySettings.localized; case .jvmArguments: Messages.CoreMemorySettings.jvmOverride.localized } }
    }
    public var maximumBytes: Int64
    public var minimumBytes: Int64
    public var initialBytes: Int64
    public var metaspaceBytes: Int64?
    public var maximumSource: Source
    public var initialSource: Source
    public var metaspaceSource: Source
    public var availability: MemoryAvailability?
    /// Present when the maximum came from automatic estimation.
    public var estimate: MemoryEstimate? = nil
    public var maximumMB: Int { Int((maximumBytes + 1_048_575) / 1_048_576) }
    public var summary: String { Messages.CoreMemorySettings.memorySummary(String(describing: Self.size(maximumBytes)), String(describing: initialBytes == 0 ? Messages.CoreMemorySettings.automaticallyManagedMemory.localized : Self.size(initialBytes)), maximumSource.title).localized + (metaspaceBytes.map { " · Metaspace ≤ \(Self.size($0))" } ?? "") }
    /// The estimate's inputs and any hardware shortfall, for records and diagnostics.
    public var estimateDetail: String? {
        guard maximumSource == .automatic, let estimate else { return nil }
        guard estimate.constrained else { return estimate.basis }
        return estimate.basis + " · " + Messages.CoreMemoryEstimate.constrained(String(describing: Self.size(Int64(estimate.demandMB) * 1_048_576)), String(describing: Self.size(Int64(estimate.maximumMB) * 1_048_576))).localized
    }
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

