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
    public static func join(_ arguments: [String]) -> String {
        arguments.map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }.joined(separator: " ")
    }
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
        guard java.major >= manifest.requiredJava, instance.supportedJavaMajors?.isEmpty != false || instance.supportedJavaMajors!.contains(java.major) else { throw RuriError.message("所选 Java 不符合游戏或整合包的版本要求。") }
        let natives = paths.instance(instance.id).appendingPathComponent("natives")
        let jarID = manifest.jar ?? instance.gameVersion
        let jar = try LauncherPaths.safePath("\(jarID)/\(jarID).jar", within: paths.versions)
        var classpath: [String] = []
        for library in manifest.libraries where GameInstaller.allowed(library, architecture: architecture) {
            if let artifact = try library.artifact() { classpath.append(try LauncherPaths.safePath(artifact.path ?? Library.mavenPath(library.name), within: paths.libraries).path) }
        }
        classpath.append(jar.path)
        for artifact in manifest.generatedLibraries ?? [] {
            guard let relative = artifact.path, FileManager.default.fileExists(atPath: try LauncherPaths.safePath(relative, within: paths.libraries).path) else { throw RuriError.message("加载器生成文件缺失，请先修复实例。") }
        }
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
        if mainClass == "cpw.mods.bootstraplauncher.BootstrapLauncher" {
            jvm = jvm.map { value in
                guard value.hasPrefix("-DignoreList="), !value.dropFirst(13).split(separator: ",").contains(Substring(jar.lastPathComponent)) else { return value }
                return value + "," + jar.lastPathComponent
            }
        }
        if jvm.isEmpty { jvm = ["-Djava.library.path=\(natives.path)", "-cp", classpath.joined(separator: ":")] }
        // LWJGL 2 uses the AWT/AppKit thread arrangement. Forcing the GLFW/LWJGL 3
        // startup flag on it can leave the legacy OpenGL context unbound.
        let legacyLWJGL = manifest.libraries.contains { $0.name.hasPrefix("org.lwjgl.lwjgl:lwjgl:") }
        if !legacyLWJGL && !jvm.contains("-XstartOnFirstThread") { jvm.insert("-XstartOnFirstThread", at: 0) }
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
        let extraGame = try ArgumentTokenizer.split(instance.extraGameArguments ?? "").map(expand)
        let reserved: Set<String> = ["--gameDir", "--assetsDir", "--assetIndex", "--username", "--uuid", "--accessToken", "--session", "--clientId", "--xuid", "--userType", "--userProperties"]
        guard !extraGame.contains(where: { reserved.contains(String($0.split(separator: "=", maxSplits: 1).first ?? "")) }) else { throw RuriError.message("附加游戏参数不能覆盖账号身份、令牌或游戏目录。") }
        game += extraGame
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
    private var reader: ProcessOutputReader?
    private var pending = Data()
    private var formatter = GameLogFormatter()
    private var secrets: [String] = []
    private var output: (@MainActor @Sendable (String) -> Void)?
    private var onExit: (@MainActor @Sendable (GameExit) -> Void)?
    private var stopRequested = false
    public var isRunning: Bool { process?.isRunning ?? false }
    public init() {}
    public func start(plan: LaunchPlan, secrets: [String] = [], output: @escaping @MainActor @Sendable (String) -> Void, onExit: @escaping @MainActor @Sendable (GameExit) -> Void) throws {
        guard self.process == nil else { throw RuriError.message("游戏已在运行或正在结束") }
        self.secrets = secrets.filter { $0.count > 3 }; self.output = output; self.onExit = onExit; pending = Data(); formatter = GameLogFormatter()
        stopRequested = false
        let startedAt = Date()
        let process = Process(); let pipe = Pipe()
        process.executableURL = plan.executable; process.arguments = plan.arguments; process.currentDirectoryURL = plan.directory; process.environment = plan.environment
        process.standardOutput = pipe; process.standardError = pipe
        let reader = try ProcessOutputReader(handle: pipe.fileHandleForReading) { [weak self] data in
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self, reader] process in
            let status = process.terminationStatus
            let reason: GameExit.Reason = process.terminationReason == .uncaughtSignal ? .signal : .exit
            let processID = process.processIdentifier
            let endedAt = Date()
            reader.finish { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !self.pending.isEmpty { self.emit(String(decoding: self.pending, as: UTF8.self)); self.pending.removeAll() }
                    for line in self.formatter.flush() { self.redactAndSend(line) }
                    let result = GameExit(status: status, reason: reason, processID: processID, startedAt: startedAt, endedAt: endedAt, stopRequested: self.stopRequested)
                    let callback = self.onExit
                    self.process = nil; self.pipe = nil; self.reader = nil; self.onExit = nil
                    callback?(result)
                }
            }
        }
        do { try process.run(); self.process = process; self.pipe = pipe; self.reader = reader }
        catch { reader.finish {}; self.output = nil; self.onExit = nil; throw error }
    }
    public func stop() {
        guard let process, process.isRunning else { return }
        stopRequested = true
        process.terminate()
    }
    private func receive(_ data: Data) {
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            emit(String(decoding: pending[..<newline], as: UTF8.self)); pending.removeSubrange(...newline)
        }
        if pending.count > 1024 * 1024 { emit("[Ruri] 单行日志过长，已省略"); pending.removeAll() }
    }
    private func emit(_ input: String) {
        for line in formatter.consume(input) { redactAndSend(line) }
    }
    private func redactAndSend(_ input: String) {
        var text = input
        for secret in secrets { text = text.replacingOccurrences(of: secret, with: "<redacted>") }
        output?(text)
    }
}
