import Foundation

public struct LaunchPlan: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let directory: URL
    public let environment: [String: String]
    public var redactedCommand: String {
        var redactNext = false
        return ([executable.path] + arguments).map { value in
            if redactNext { redactNext = false; return "<redacted>" }
            if ["--accessToken", "--clientId", "--xuid", "--session"].contains(value) { redactNext = true }
            return value.contains(" ") ? "\"\(value)\"" : value
        }.joined(separator: " ")
    }
}

public enum ArgumentTokenizer {
    public static func split(_ input: String) throws -> [String] {
        var output: [String] = []; var token = ""; var quote: Character?; var escape = false; var started = false
        for c in input {
            if escape { token.append(c); escape = false; started = true; continue }
            if c == "\\", quote != "'" { escape = true; started = true; continue }
            if let q = quote { if c == q { quote = nil } else { token.append(c) }; continue }
            if c == "\"" || c == "'" { quote = c; started = true; continue }
            if c.isWhitespace { if started { output.append(token); token = ""; started = false } }
            else { token.append(c); started = true }
        }
        guard quote == nil, !escape else { throw RuriError.message("启动参数中的引号或反斜杠未闭合。") }
        if started { output.append(token) }
        return output
    }
}

public enum LaunchBuilder {
    public static func build(instance: GameInstance, manifest: VersionManifest, java: JavaRuntime, account: Account, accessToken: String = "0", paths: LauncherPaths) throws -> LaunchPlan {
        guard let mainClass = manifest.mainClass else { throw RuriError.message("启动清单没有主类") }
        guard manifest.inheritsFrom == nil else { throw RuriError.message("启动清单尚未合并父版本") }
        guard (512...131_072).contains(instance.memoryMB), (320...16_384).contains(instance.width), (240...16_384).contains(instance.height) else { throw RuriError.message("内存或窗口大小设置无效") }
        let architecture = GameInstaller.architecture(for: manifest)
        guard java.architecture == architecture else { throw RuriError.message("Java 与游戏原生库的架构不匹配。需要 \(architecture)。") }
        let natives = paths.instance(instance.id).appendingPathComponent("natives")
        let jarID = manifest.jar ?? instance.gameVersion
        let jar = try LauncherPaths.safePath("\(jarID)/\(jarID).jar", within: paths.versions)
        var classpath: [String] = []
        for library in manifest.libraries where GameInstaller.allowed(library, architecture: architecture) {
            if let artifact = try library.artifact() { classpath.append(try LauncherPaths.safePath(artifact.path ?? Library.mavenPath(library.name), within: paths.libraries).path) }
        }
        classpath.append(jar.path)
        for file in classpath where !FileManager.default.fileExists(atPath: file) { throw RuriError.message("游戏文件缺失：\(URL(fileURLWithPath: file).lastPathComponent)。请先修复实例。") }
        let values: [String: String] = [
            "auth_player_name": account.username, "version_name": manifest.id,
            "game_directory": paths.game(instance.id).path, "assets_root": paths.assets.path,
            "assets_index_name": manifest.assetIndex?.id ?? manifest.assets ?? "legacy",
            "auth_uuid": account.uuid, "auth_access_token": accessToken,
            "auth_session": account.kind == .offline ? "0" : "token:\(accessToken):\(account.uuid)",
            "clientid": "", "auth_xuid": "", "user_type": account.kind == .microsoft ? "msa" : "legacy",
            "version_type": manifest.type ?? "release", "user_properties": "{}",
            "natives_directory": natives.path, "launcher_name": "Ruri", "launcher_version": "0.1.0",
            "classpath": classpath.joined(separator: ":"), "classpath_separator": ":",
            "library_directory": paths.libraries.path, "primary_jar": jar.path, "primary_jar_name": jar.lastPathComponent,
            "resolution_width": String(instance.width), "resolution_height": String(instance.height),
            "game_assets": paths.assets.appendingPathComponent("virtual/\(manifest.assetIndex?.id ?? "legacy")").path
        ]
        func expand(_ input: String) throws -> String {
            var result = input
            for (key, value) in values { result = result.replacingOccurrences(of: "${\(key)}", with: value) }
            guard result.range(of: #"\$\{[^}]+\}"#, options: .regularExpression) == nil else { throw RuriError.message("启动清单包含未支持的变量：\(input)") }
            return result
        }
        let features = ["has_custom_resolution": true, "is_demo_user": false, "has_quick_plays_support": false]
        var jvm = try (manifest.arguments?.jvm ?? []).flatMap { $0.values(architecture: architecture, features: features) }.map(expand)
        if jvm.isEmpty { jvm = ["-Djava.library.path=\(natives.path)", "-cp", classpath.joined(separator: ":")] }
        if !jvm.contains("-XstartOnFirstThread") { jvm.insert("-XstartOnFirstThread", at: 0) }
        jvm.insert(contentsOf: ["-Xms512M", "-Xmx\(instance.memoryMB)M", "-Dfile.encoding=UTF-8", "-Dapple.awt.application.name=\(instance.name)", "-Dlog4j2.formatMsgNoLookups=true"], at: 0)
        if let logging = manifest.logging?.client {
            let file = try LauncherPaths.safePath("log_configs/\(logging.file.id)", within: paths.assets)
            jvm.append(logging.argument.replacingOccurrences(of: "${path}", with: file.path))
        }
        let extras = try ArgumentTokenizer.split(instance.extraJVMArguments)
        guard !extras.contains(where: { $0.hasPrefix("@") || ["-jar", "--class-path", "-classpath", "-cp"].contains($0) }) else { throw RuriError.message("附加 JVM 参数不能覆盖游戏主类或 classpath。") }
        jvm += extras
        var game: [String]
        if let legacy = manifest.minecraftArguments { game = try ArgumentTokenizer.split(legacy).map(expand) }
        else { game = try (manifest.arguments?.game ?? []).flatMap { $0.values(architecture: architecture, features: features) }.map(expand) }
        if !game.contains("--width") { game += ["--width", String(instance.width), "--height", String(instance.height)] }
        var env = ProcessInfo.processInfo.environment
        for key in ["JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS", "CLASSPATH"] { env.removeValue(forKey: key) }
        env["JAVA_HOME"] = URL(fileURLWithPath: java.path).deletingLastPathComponent().deletingLastPathComponent().path
        return LaunchPlan(executable: URL(fileURLWithPath: java.path), arguments: jvm + [mainClass] + game, directory: paths.game(instance.id), environment: env)
    }
}

@MainActor
public final class GameProcess {
    private var process: Process?
    private var pipe: Pipe?
    private var pending = Data()
    private var secrets: [String] = []
    private var output: (@MainActor @Sendable (String) -> Void)?
    private var onExit: (@MainActor @Sendable (Int32) -> Void)?
    public var isRunning: Bool { process?.isRunning ?? false }
    public init() {}
    public func start(plan: LaunchPlan, secrets: [String] = [], output: @escaping @MainActor @Sendable (String) -> Void, onExit: @escaping @MainActor @Sendable (Int32) -> Void) throws {
        guard !isRunning else { throw RuriError.message("游戏已在运行") }
        self.secrets = secrets.filter { $0.count > 3 }; self.output = output; self.onExit = onExit; pending = Data()
        let process = Process(); let pipe = Pipe()
        process.executableURL = plan.executable; process.arguments = plan.arguments; process.currentDirectoryURL = plan.directory; process.environment = plan.environment
        process.standardOutput = pipe; process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty { Task { @MainActor in self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.pipe?.fileHandleForReading.readabilityHandler = nil
                if !self.pending.isEmpty { self.emit(String(decoding: self.pending, as: UTF8.self)); self.pending.removeAll() }
                self.onExit?(status); self.process = nil; self.pipe = nil
            }
        }
        try process.run(); self.process = process; self.pipe = pipe
    }
    public func stop() { process?.terminate() }
    private func receive(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            emit(String(decoding: pending[..<newline], as: UTF8.self)); pending.removeSubrange(...newline)
        }
        if pending.count > 1024 * 1024 { emit("[Ruri] 单行日志过长，已省略"); pending.removeAll() }
    }
    private func emit(_ input: String) {
        var text = input
        for secret in secrets { text = text.replacingOccurrences(of: secret, with: "<redacted>") }
        output?(text)
    }
}
