import RuriLocalization
import Foundation

public struct LaunchPlan: Codable, Sendable {
    public let executable: URL
    public var arguments: [String]
    public let directory: URL
    public let environment: [String: String]
    public var nativeQuitSupported: Bool?
    public var memory: LaunchMemory?
    public var customEnvironmentNames: [String]?
    public var commands: LaunchCommands?
    public var wrapper: [String]?
    public var offlineSkin: OfflineSkinLaunch? = nil
    public var debugLogging: Bool? = nil
    public var host: GameHostPlan? = nil
    var processExecutable: URL { wrapper?.first.map { URL(fileURLWithPath: $0) } ?? executable }
    var processArguments: [String] { wrapper?.isEmpty == false ? Array(wrapper!.dropFirst()) + [executable.path] + arguments : arguments }
    public var environmentRedactions: [String] { (customEnvironmentNames ?? []).compactMap { environment[$0] }.filter { $0.count > 3 } }
    public var redactedCommand: String {
        var redactNext = false
        return ([processExecutable.path] + processArguments).map { value in
            if redactNext { redactNext = false; return "<redacted>" }
            if ["--accessToken", "--clientId", "--xuid", "--session", "--userProperties"].contains(value) { redactNext = true }
            if value.hasPrefix("-Dauthlibinjector.yggdrasil.prefetched=") { return "-Dauthlibinjector.yggdrasil.prefetched=<metadata>" }
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
        guard quote == nil, !escape else { throw RuriError.message(Messages.CoreLaunch.unclosedLaunchQuoting) }
        if started { output.append(token) }
        return output
    }
}

public enum LaunchBuilder {
    public static func build(instance: GameInstance, manifest: VersionManifest, java: JavaRuntime, account: Account, accessToken: String = "0", paths: LauncherPaths, world: WorldSnapshot? = nil, externalAuth: ExternalAuthLaunch? = nil, offlineSkin: OfflineSkinLaunch? = nil) throws -> LaunchPlan {
        guard (account.kind == .external) == (externalAuth != nil) else { throw RuriError.message(Messages.CoreLaunch.externalAuthRequired) }
        if let offlineSkin {
            guard account.kind == .offline, offlineSkin.account == account else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
            try offlineSkin.validate()
        }
        guard paths.repositoryImportID == nil else { throw RuriError.message(Messages.CoreLaunch.packImportIncomplete) }
        let instance = try instance.resolvingPersistedLaunchSettings(paths: paths)
        try paths.validateBinding(instance)
        if let world { try WorldQuickPlay.validate(world, instance: instance, manifest: manifest, paths: paths) }
        guard let mainClass = manifest.mainClass else { throw RuriError.message(Messages.CoreLaunch.mainClassMissing) }
        guard manifest.inheritsFrom == nil else { throw RuriError.message(Messages.CoreLaunch.parentManifestUnmerged) }
        guard (512...131_072).contains(instance.memoryMB), (320...16_384).contains(instance.width), (240...16_384).contains(instance.height) else { throw RuriError.message(Messages.CoreLaunch.invalidMemoryOrWindow) }
        let architecture = GameInstaller.architecture(for: manifest)
        guard manifest.compatibilityRules?.isEmpty != false || Rule.allows(manifest.compatibilityRules, architecture: architecture) else {
            throw RuriError.message(Messages.CoreLaunch.unsupportedArchitecture)
        }
        guard java.architecture == architecture else { throw RuriError.message(Messages.CoreLaunch.nativeArchitectureMismatch(String(describing: architecture))) }
        try GameJavaRequirement(instance: instance, manifest: manifest).validate(java)
        let natives = paths.instance(instance.id).appendingPathComponent("natives")
        let resources = try paths.resources(for: instance)
        let jarID = manifest.jar ?? instance.gameVersion
        let jar = try LauncherPaths.safePath("\(jarID)/\(jarID).jar", within: resources.versions)
        // Bootstrap loaders compare classpath and module-path locations. Expand
        // both from the same canonical root when the library folder is an alias.
        let libraries = resources.libraries.standardizedFileURL.resolvingSymlinksInPath()
        var classpath: [String] = []
        for library in manifest.libraries where GameInstaller.allowed(library, architecture: architecture) {
            if let artifact = try library.artifact() {
                let file = try resources.libraryFile(artifact, fallback: Library.mavenPath(library.name))
                if library.includeInClasspath == false {
                    guard FileManager.default.fileExists(atPath: file.path) else { throw RuriError.message(Messages.CoreLaunch.gameFilesMissing(file.lastPathComponent)) }
                } else { classpath.append(file.path) }
            }
        }
        classpath.append(jar.path)
        // Native and ordinary declarations can share a Java artifact. Keep
        // their metadata for extraction, but pass each resolved JAR only once
        // to bootstrap loaders, preserving the original classpath precedence.
        var seen = Set<String>()
        classpath = classpath.filter { seen.insert($0).inserted }
        for artifact in manifest.generatedLibraries ?? [] {
            guard FileManager.default.fileExists(atPath: try resources.libraryFile(artifact).path) else { throw RuriError.message(Messages.CoreLaunch.generatedFilesMissing) }
        }
        for file in classpath where !FileManager.default.fileExists(atPath: file) { throw RuriError.message(Messages.CoreLaunch.gameFilesMissing(String(describing: URL(fileURLWithPath: file).lastPathComponent))) }
        let values: [String: String] = [
            "auth_player_name": account.username, "version_name": manifest.id,
            "game_directory": paths.game(instance.id).path, "assets_root": resources.assets.path,
            "assets_index_name": manifest.assetIndex?.id ?? manifest.assets ?? "legacy",
            "auth_uuid": account.uuid, "auth_access_token": accessToken,
            "auth_session": account.kind == .offline && offlineSkin == nil ? "0" : (account.kind != .microsoft ? accessToken : "token:\(accessToken):\(account.uuid)"),
            "clientid": "", "auth_xuid": "", "user_type": account.kind == .microsoft || offlineSkin != nil ? "msa" : (account.kind == .external ? "mojang" : "legacy"),
            "version_type": manifest.type ?? "release", "user_properties": externalAuth?.userProperties ?? "{}",
            "natives_directory": natives.path, "launcher_name": "Ruri", "launcher_version": "0.1.0",
            "classpath": classpath.joined(separator: ":"), "classpath_separator": ":",
            "library_directory": libraries.path, "version_directory": jar.deletingLastPathComponent().path, "primary_jar": jar.path, "primary_jar_name": jar.lastPathComponent,
            "resolution_width": String(instance.width), "resolution_height": String(instance.height),
            "game_assets": resources.assets.appendingPathComponent("virtual/\(manifest.assetIndex?.id ?? "legacy")").path,
            "quickPlaySingleplayer": world?.folder ?? "", "quickPlayMultiplayer": "", "quickPlayRealms": "",
            "quickPlayPath": paths.instance(instance.id).appendingPathComponent("quick-play.json").path
        ]
        func expand(_ input: String) throws -> String {
            var result = input
            for (key, value) in values { result = result.replacingOccurrences(of: "${\(key)}", with: value) }
            guard result.range(of: #"\$\{[^}]+\}"#, options: .regularExpression) == nil else { throw RuriError.message(Messages.CoreLaunch.unsupportedManifestVariable(String(describing: input))) }
            return result
        }
        let features = ["has_custom_resolution": true, "is_demo_user": false, "has_quick_plays_support": world != nil,
                        "is_quick_play_singleplayer": world != nil, "is_quick_play_multiplayer": false, "is_quick_play_realms": false]
        var jvm = try (manifest.arguments?.jvm ?? []).flatMap { $0.values(architecture: architecture, features: features) }.map(expand)
        jvm = ForgeLaunchArguments.bootstrap(jvm, manifest: manifest, classpath: classpath, client: jar)
        if jvm.isEmpty { jvm = ["-Djava.library.path=\(natives.path)", "-cp", classpath.joined(separator: ":")] }
        // LWJGL 2 uses the AWT/AppKit thread arrangement. Forcing the GLFW/LWJGL 3
        // startup flag on it can leave the legacy OpenGL context unbound.
        let legacyLWJGL = manifest.libraries.contains { $0.name.hasPrefix("org.lwjgl.lwjgl:lwjgl:") }
        if !legacyLWJGL && !jvm.contains("-XstartOnFirstThread") { jvm.insert("-XstartOnFirstThread", at: 0) }
        let baseMemory = try instance.frozenMemory ?? MemorySettings(maximumMB: instance.memoryMB).resolve()
        var memoryArguments = jvm
        jvm.insert(contentsOf: baseMemory.arguments + ["-Dfile.encoding=UTF-8", "-Dapple.awt.application.name=\(instance.name)", "-Dlog4j2.formatMsgNoLookups=true"], at: 0)
        if let logging = manifest.logging?.client {
            let file = try LauncherPaths.safePath("log_configs/\(logging.file.id)", within: resources.assets)
            jvm.append(try expand(logging.argument.replacingOccurrences(of: "${path}", with: file.path)))
        }
        let extras = try ArgumentTokenizer.split(instance.extraJVMArguments).map(expand)
        guard !extras.contains(where: { $0.hasPrefix("@") || ["-jar", "--class-path", "-classpath", "-cp"].contains($0) }) else { throw RuriError.message(Messages.CoreLaunch.jvmArgumentsOverride) }
        jvm += extras
        if let externalAuth { jvm += try externalAuth.arguments(for: account) }
        memoryArguments += extras
        let memory = try JVMHeapArguments.resolve(base: baseMemory, arguments: memoryArguments)
        var game: [String]
        if let legacy = manifest.minecraftArguments { game = try ArgumentTokenizer.split(legacy).map(expand) }
        else { game = try (manifest.arguments?.game ?? []).flatMap { $0.values(architecture: architecture, features: features) }.map(expand) }
        let extraGame = try ArgumentTokenizer.split(instance.extraGameArguments ?? "").map(expand)
        let reserved: Set<String> = ["--gameDir", "--assetsDir", "--assetIndex", "--username", "--uuid", "--accessToken", "--session", "--clientId", "--xuid", "--userType", "--userProperties"]
        guard !extraGame.contains(where: { reserved.contains(String($0.split(separator: "=", maxSplits: 1).first ?? "")) }) else { throw RuriError.message(Messages.CoreLaunch.gameArgumentsOverride) }
        game += extraGame
        if let world { game = WorldQuickPlay.applying(world, to: game, instance: instance, paths: paths) }
        func hasOption(_ name: String) -> Bool { game.contains { $0 == name || $0.hasPrefix(name + "=") } }
        if !hasOption("--width") { game += ["--width", String(instance.width)] }
        if !hasOption("--height") { game += ["--height", String(instance.height)] }
        if instance.fullscreen == true && !hasOption("--fullscreen") { game.append("--fullscreen") }
        let customEnvironment = try LaunchEnvironment(instance.environmentVariables ?? "")
        var env = customEnvironment.applying(to: ProcessInfo.processInfo.environment, java: URL(fileURLWithPath: java.path))
        let commands = instance.launchCommands ?? .init()
        try commands.validate()
        if commands.enabled {
            env.merge(["RURI_GAME_DIRECTORY": paths.game(instance.id).path, "RURI_INSTANCE_DIRECTORY": paths.instance(instance.id).path,
                       "RURI_INSTANCE_NAME": instance.name, "RURI_INSTANCE_ID": instance.id.uuidString, "RURI_GAME_VERSION": instance.gameVersion, "RURI_JAVA": java.path]) { _, value in value }
        }
        let wrapper = try commands.resolveWrapper(environment: env, directory: paths.game(instance.id))
        let nativeQuitSupported = !legacyLWJGL && manifest.libraries.contains { $0.name.hasPrefix("org.lwjgl:lwjgl-glfw:") }
        var offlineSkin = offlineSkin
        offlineSkin?.argumentIndex = jvm.count
        return LaunchPlan(executable: URL(fileURLWithPath: java.path), arguments: jvm + [mainClass] + game, directory: paths.game(instance.id), environment: env, nativeQuitSupported: nativeQuitSupported, memory: memory, customEnvironmentNames: customEnvironment.entries.map(\.name), commands: commands.enabled && !commands.isEmpty ? commands : nil, wrapper: wrapper.isEmpty ? nil : wrapper, offlineSkin: offlineSkin, debugLogging: instance.launchPresentation?.debugLogging == true, host: GameHostPlan(instanceID: instance.id, name: instance.name, iconPNG: instance.iconPNG ?? instance.iconStyle.flatMap(InstanceIconRenderer.launchPNG), javaVersion: java.version, architecture: java.architecture, settings: instance.macOSGameSettings ?? .init(), fullscreen: instance.fullscreen == true))
    }
}
