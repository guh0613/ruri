import RuriLocalization
import Foundation
import Darwin

public struct JavaRuntime: Codable, Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let version: String
    public let major: Int
    public let architecture: String
    public let vendor: String
    public var isNative: Bool { architecture == Self.hostArchitecture }
    public static var hostArchitecture: String {
        #if arch(arm64)
        "aarch64"
        #else
        "x86_64"
        #endif
    }
    public var label: String { "Java \(major) · \(architecture == "aarch64" ? "Apple Silicon" : "Intel") · \(vendor)" }
    public init(path: String, version: String, major: Int, architecture: String, vendor: String) {
        self.path = path; self.version = version; self.major = major; self.architecture = architecture; self.vendor = vendor
    }
}

public enum ProcessRunner {
    public static func run(_ executable: URL, arguments: [String], directory: URL? = nil, timeout: TimeInterval = 10) throws -> (Int32, String) {
        let process = Process(), finished = DispatchSemaphore(value: 0)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-java-probe-" + UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: output) }
        process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
        process.standardOutput = handle; process.standardError = handle
        var environment = ProcessInfo.processInfo.environment
        for key in ["JAVA_TOOL_OPTIONS", "JDK_JAVA_OPTIONS", "_JAVA_OPTIONS", "CLASSPATH"] { environment.removeValue(forKey: key) }
        process.environment = environment
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + timeout) == .success else {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = finished.wait(timeout: .now() + 1)
            throw RuriError.message(Messages.CoreJavaRuntime.environmentText1)
        }
        let reader = try FileHandle(forReadingFrom: output); defer { try? reader.close() }
        let data = try reader.read(upToCount: 1024 * 1024) ?? Data()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

public enum JavaDiscovery {
    public static func scan(paths: LauncherPaths, extra: [String] = []) async -> [JavaRuntime] {
        await inventory(paths: paths, extra: extra).compactMap(\.runtime)
    }
    public static func executable(in selection: URL) throws -> URL {
        let selection = selection.standardizedFileURL
        let candidates = [selection] + ["Contents/Home/bin/java", "bin/java", "jre.bundle/Contents/Home/bin/java", "libexec/openjdk.jdk/Contents/Home/bin/java"].map { selection.appendingPathComponent($0) }
        guard let executable = candidates.first(where: { $0.lastPathComponent == "java" && FileManager.default.isExecutableFile(atPath: $0.path) && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }) else {
            throw RuriError.message(Messages.CoreJavaRuntime.executableText1)
        }
        return executable
    }
    public static func sameExecutable(_ first: String, _ second: String) -> Bool {
        URL(fileURLWithPath: first).standardizedFileURL.resolvingSymlinksInPath() == URL(fileURLWithPath: second).standardizedFileURL.resolvingSymlinksInPath()
    }
    public static func inspect(_ path: String) throws -> JavaRuntime {
        guard FileManager.default.isExecutableFile(atPath: path) else { throw RuriError.message(Messages.CoreJavaRuntime.inspectText1(String(describing: path))) }
        let (status, text) = try ProcessRunner.run(URL(fileURLWithPath: path), arguments: ["-XshowSettings:properties", "-version"])
        guard status == 0 else { throw RuriError.message(Messages.CoreJavaRuntime.inspectText2(String(describing: path))) }
        func property(_ key: String) -> String? {
            text.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + " = ") }.map { String($0.components(separatedBy: " = ").dropFirst().joined(separator: " = ")) }
        }
        guard let version = property("java.version"), let arch = property("os.arch") else { throw RuriError.message(Messages.CoreJavaRuntime.archText1) }
        let components = version.split(whereSeparator: { !$0.isNumber })
        let major = Int(components.first == "1" ? (components.dropFirst().first ?? "0") : (components.first ?? "0")) ?? 0
        guard major > 0 else { throw RuriError.message(Messages.CoreJavaRuntime.majorText1(String(describing: version))) }
        return JavaRuntime(path: path, version: version, major: major, architecture: arch == "arm64" ? "aarch64" : (arch == "amd64" ? "x86_64" : arch), vendor: property("java.vendor") ?? "Java")
    }
    public static func select(from runtimes: [JavaRuntime], major: Int, architecture: String? = nil, preferredPath: String? = nil) throws -> JavaRuntime {
        if let path = preferredPath {
            guard let selected = runtimes.first(where: { $0.path == path }) ?? runtimes.first(where: { sameExecutable($0.path, path) }) else { throw RuriError.message(Messages.CoreJavaRuntime.selectedText1) }
            guard selected.major >= major else { throw RuriError.message(Messages.CoreJavaRuntime.selectedText2(String(describing: major), String(describing: selected.major))) }
            if let architecture, selected.architecture != architecture { throw RuriError.message(Messages.CoreJavaRuntime.architectureText1(String(describing: architecture))) }
            return selected
        }
        let compatible = runtimes.filter { $0.major == major && (architecture == nil || $0.architecture == architecture) }
        guard let runtime = compatible.sorted(by: {
            if $0.isNative != $1.isNative { return $0.isNative }
            let order = $0.version.compare($1.version, options: .numeric)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedDescending
        }).first else {
            throw RuriError.message(Messages.CoreJavaRuntime.orderText1(String(describing: major), String(describing: architecture == "x86_64" ? "（Intel / Rosetta）" : "")))
        }
        return runtime
    }
}
