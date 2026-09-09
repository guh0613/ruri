import Foundation

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
    public static func run(_ executable: URL, arguments: [String], directory: URL? = nil) throws -> (Int32, String) {
        let process = Process(); let pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = directory
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

public enum JavaDiscovery {
    public static func scan(paths: LauncherPaths, extra: [String] = []) async -> [JavaRuntime] {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var candidates = Set(extra)
            let home = fm.homeDirectoryForCurrentUser
            let folders = [URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines"), home.appendingPathComponent("Library/Java/JavaVirtualMachines"), paths.runtimes,
                           URL(fileURLWithPath: "/opt/homebrew/opt"), URL(fileURLWithPath: "/usr/local/opt")]
            for folder in folders {
                for child in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                    if folder.path.hasSuffix("/opt"), !child.lastPathComponent.contains("openjdk") { continue }
                    if child.lastPathComponent.hasPrefix(".") { continue }
                    for suffix in ["Contents/Home/bin/java", "bin/java", "jre.bundle/Contents/Home/bin/java", "libexec/openjdk.jdk/Contents/Home/bin/java"] {
                        let file = child.appendingPathComponent(suffix)
                        if fm.isExecutableFile(atPath: file.path) { candidates.insert(file.resolvingSymlinksInPath().path) }
                    }
                }
            }
            if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] { candidates.insert(javaHome + "/bin/java") }
            var result: [JavaRuntime] = []
            for path in candidates.sorted() { if let runtime = try? inspect(path) { result.append(runtime) } }
            return result.sorted { $0.isNative != $1.isNative ? $0.isNative : $0.major > $1.major }
        }.value
    }
    public static func inspect(_ path: String) throws -> JavaRuntime {
        guard FileManager.default.isExecutableFile(atPath: path) else { throw RuriError.message("Java 不可执行：\(path)") }
        let (status, text) = try ProcessRunner.run(URL(fileURLWithPath: path), arguments: ["-XshowSettings:properties", "-version"])
        guard status == 0 else { throw RuriError.message("无法运行 Java：\(path)") }
        func property(_ key: String) -> String? {
            text.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + " = ") }.map { String($0.components(separatedBy: " = ").dropFirst().joined(separator: " = ")) }
        }
        guard let version = property("java.version"), let arch = property("os.arch") else { throw RuriError.message("无法识别 Java 版本") }
        let components = version.split(whereSeparator: { !$0.isNumber })
        let major = Int(components.first == "1" ? (components.dropFirst().first ?? "0") : (components.first ?? "0")) ?? 0
        return JavaRuntime(path: path, version: version, major: major, architecture: arch == "arm64" ? "aarch64" : (arch == "amd64" ? "x86_64" : arch), vendor: property("java.vendor") ?? "Java")
    }
    public static func select(from runtimes: [JavaRuntime], major: Int, architecture: String? = nil, preferredPath: String? = nil) throws -> JavaRuntime {
        if let path = preferredPath {
            guard let selected = runtimes.first(where: { $0.path == path }) else { throw RuriError.message("指定的 Java 不可用，请在实例设置中重新选择。") }
            guard selected.major >= major else { throw RuriError.message("此游戏需要 Java \(major)，当前指定 Java \(selected.major)。") }
            if let architecture, selected.architecture != architecture { throw RuriError.message("Java 架构与游戏原生库不匹配，需要 \(architecture)。") }
            return selected
        }
        let compatible = runtimes.filter { $0.major == major && (architecture == nil || $0.architecture == architecture) }
        guard let runtime = compatible.sorted(by: { $0.isNative && !$1.isNative }).first else {
            throw RuriError.message("需要 Java \(major)\(architecture == "x86_64" ? "（Intel / Rosetta）" : "")。请到设置 → Java 安装或选择该版本。")
        }
        return runtime
    }
}
