import Foundation

/// The VM options one Java runtime accepts. An unrecognized `-XX` flag or
/// launcher option stops the JVM before the game starts, so launch tuning only
/// passes what the runtime itself listed: no table of which vendor or version
/// has which flag to keep current, and OpenJ9, which lists no HotSpot flags,
/// simply gets none.
public struct JavaCapabilities: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case product
        /// Needs `-XX:+UnlockExperimentalVMOptions` before it.
        case experimental
        /// Needs `-XX:+UnlockDiagnosticVMOptions` before it.
        case diagnostic
    }
    public var flags: [String: Kind]
    /// `--sun-misc-unsafe-memory-access`, the JEP 471 switch for the memory
    /// methods of sun.misc.Unsafe. Older runtimes refuse to start with it.
    public var unsafeMemoryAccessOption: Bool
    public init(flags: [String: Kind], unsafeMemoryAccessOption: Bool = false) {
        self.flags = flags; self.unsafeMemoryAccessOption = unsafeMemoryAccessOption
    }
    public func kind(_ flag: String) -> Kind? { flags[flag] }

    /// Reads `-XX:+PrintFlagsFinal` output, where each flag is one line:
    /// `type name = value {kind} {origin}`. The value can be empty and the kind
    /// can carry qualifiers such as `{C2 experimental}` or `{product lp64_product}`.
    public static func parse(_ output: String) -> [String: Kind] {
        var result: [String: Kind] = [:]
        for line in output.split(separator: "\n") {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.count >= 3, tokens[2] == "=", let brace = line.firstIndex(of: "{") else { continue }
            let qualifiers = line[brace...]
            result[String(tokens[1])] = qualifiers.contains("experimental") ? .experimental : qualifiers.contains("diagnostic") ? .diagnostic : .product
        }
        return result
    }

    /// Probes off the caller's thread; each executable is started at most once
    /// while it stays unchanged. With a cache directory the result also
    /// outlives this process. Nil when the runtime could not be read, which
    /// tuning treats as knowing no flags at all.
    public static func load(for java: JavaRuntime, cache: URL? = nil) async -> JavaCapabilities? {
        let executable = URL(fileURLWithPath: java.path).resolvingSymlinksInPath()
        let stamp = (try? executable.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate?.timeIntervalSinceReferenceDate) ?? -1
        let key = JavaCapabilitiesCache.Key(path: executable.path, version: java.version, stamp: stamp)
        if let hit = JavaCapabilitiesCache.shared.lookup(key) { return hit }
        let file = cache?.appendingPathComponent("java-capabilities.json")
        let major = java.major
        let loaded = await Task.detached(priority: .userInitiated) { () -> JavaCapabilities? in
            if let file, let stored = JavaCapabilitiesCache.read(file)[key.path], stored.key == key { return stored.capabilities }
            guard let probed = probe(executable, major: major) else { return nil }
            if let file { JavaCapabilitiesCache.write(probed, for: key, to: file) }
            return probed
        }.value
        if let loaded { JavaCapabilitiesCache.shared.store(loaded, for: key) }
        return loaded
    }

    static func probe(_ executable: URL, major: Int) -> JavaCapabilities? {
        let listing = ["-XX:+UnlockExperimentalVMOptions", "-XX:+UnlockDiagnosticVMOptions", "-XX:+PrintFlagsFinal"]
        // The option exists from Java 23; asking earlier runtimes only costs a
        // second start. A refusal here means this runtime lacks it, not that the
        // runtime is unusable, so the plain listing is tried next.
        if major >= 23, let (status, text) = try? ProcessRunner.run(executable, arguments: listing + ["--sun-misc-unsafe-memory-access=allow", "-version"]), status == 0 {
            return .init(flags: parse(text), unsafeMemoryAccessOption: true)
        }
        guard let (status, text) = try? ProcessRunner.run(executable, arguments: listing + ["-version"]), status == 0 else { return nil }
        return .init(flags: parse(text))
    }
}

final class JavaCapabilitiesCache: @unchecked Sendable {
    struct Key: Codable, Hashable { let path: String; let version: String; let stamp: Double }
    struct Entry: Codable { let key: Key; let capabilities: JavaCapabilities }
    static let shared = JavaCapabilitiesCache()
    private let lock = NSLock()
    private var entries: [Key: JavaCapabilities] = [:]
    func lookup(_ key: Key) -> JavaCapabilities? {
        lock.lock(); defer { lock.unlock() }
        return entries[key]
    }
    func store(_ capabilities: JavaCapabilities, for key: Key) {
        lock.lock(); defer { lock.unlock() }
        entries[key] = capabilities
    }

    /// Entries by executable path; an unreadable file is an empty cache.
    static func read(_ file: URL) -> [String: Entry] {
        (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: file))) ?? [:]
    }
    /// Last writer wins: a lost entry only costs one more probe.
    static func write(_ capabilities: JavaCapabilities, for key: Key, to file: URL) {
        var entries = read(file)
        entries[key.path] = .init(key: key, capabilities: capabilities)
        // Runtimes that no longer exist would otherwise stay forever.
        entries = entries.filter { FileManager.default.fileExists(atPath: $0.key) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: file, options: .atomic)
    }
}
