import Foundation
import RuriLocalization

struct GameHostRequest: Encodable, Sendable {
    let version = 1
    let sessionID: UUID
    let instanceID: UUID
    let javaExecutable: String
    let jliLibrary: String
    let javaVersion: String
    let directory: String
    let arguments: [String]
    let directArguments: [String]
    let name: String
    let iconPNG: Data?
    let instanceAppearance: Bool
    let nativeFullscreen: Bool
}

struct GameHostLaunch {
    let executable: URL
    let arguments: [String]
    let request: GameHostRequest

    static func executable(beside binary: URL? = Bundle.main.executableURL) -> URL? {
        guard let directory = binary?.deletingLastPathComponent() else { return nil }
        let relative = "RuriGame.app/Contents/MacOS/ruri-game"
        return [directory.deletingLastPathComponent().appendingPathComponent("Helpers").appendingPathComponent(relative),
                directory.appendingPathComponent(relative)].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func prepare(_ plan: LaunchPlan, sessionID: UUID, host: URL? = nil) -> (GameHostLaunch?, GameHostStatus) {
        func fallback(_ reason: String) -> (GameHostLaunch?, GameHostStatus) { (nil, .init(backend: .java, fallback: reason)) }
        guard let game = plan.host, game.settings.enabled else { return fallback("disabled") }
        guard plan.wrapper?.isEmpty != false else { return fallback("wrapper") }
        guard ["aarch64", "arm64", "x86_64"].contains(game.architecture) else { return fallback("architecture") }
        guard let host = host ?? executable(), FileManager.default.isExecutableFile(atPath: host.path) else { return fallback("hostMissing") }
        let java = plan.executable.resolvingSymlinksInPath()
        let home = java.deletingLastPathComponent().deletingLastPathComponent()
        let libraries = ["lib/libjli.dylib", "lib/jli/libjli.dylib", "jre/lib/jli/libjli.dylib"]
        guard let library = libraries.map({ home.appendingPathComponent($0) }).first(where: { FileManager.default.isReadableFile(atPath: $0.path) }) else { return fallback("runtimeMissing") }
        let fullscreen = game.fullscreen && game.settings.nativeFullscreen
        let request = GameHostRequest(sessionID: sessionID, instanceID: game.instanceID, javaExecutable: java.path,
            jliLibrary: library.path, javaVersion: game.javaVersion, directory: plan.directory.path,
            arguments: fullscreen ? plan.arguments.filter { $0 != "--fullscreen" } : plan.arguments,
            directArguments: plan.arguments, name: game.name, iconPNG: game.settings.instanceAppearance ? game.iconPNG : nil,
            instanceAppearance: game.settings.instanceAppearance, nativeFullscreen: fullscreen)
        // arch replaces itself with the host, retaining the monitored PID and stdin.
        let architecture = game.architecture == "x86_64" ? "-x86_64" : "-arm64"
        return (.init(executable: URL(fileURLWithPath: "/usr/bin/arch"), arguments: [architecture, host.path, "run"], request: request), .init(backend: .native))
    }
}

extension GameHostStatus {
    public var summary: String {
        if let failure { return Messages.GameHost.failed(Self.explanation(failure)).localized }
        if backend == .java { return Messages.GameHost.compatibility(Self.explanation(fallback ?? "disabled")).localized }
        if fullscreen { return Messages.GameHost.fullscreen.localized }
        if windowReadyAt != nil { return Messages.GameHost.windowReady.localized }
        return jvmStarted ? Messages.GameHost.jvmStarting.localized : Messages.GameHost.starting.localized
    }
    static func explanation(_ code: String) -> String {
        switch code {
        case "disabled": Messages.GameHost.disabled.localized
        case "wrapper": Messages.GameHost.wrapper.localized
        case "architecture": Messages.GameHost.architecture.localized
        case "hostMissing": Messages.GameHost.hostMissing.localized
        case "runtimeMissing", "runtimeLoad", "runtimeEntry": Messages.GameHost.runtimeUnavailable.localized
        case "directory": Messages.GameHost.directory.localized
        case "javaExec": Messages.GameHost.javaExec.localized
        case "transport": Messages.GameHost.transport.localized
        default: Messages.GameHost.invalidRequest.localized
        }
    }
}
