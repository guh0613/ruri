import Foundation
import RuriLocalization

public enum LaunchDestination: Equatable, Codable, Sendable {
    case normal
    case world(folder: String)
    case server(ServerAddress)
    public static func resolve(worldFolder: String?, serverAddress: String?) throws -> Self {
        guard worldFolder == nil || serverAddress == nil else { throw RuriError.message(Messages.Servers.destinationConflict) }
        if let worldFolder { return .world(folder: worldFolder) }
        if let serverAddress { return .server(try ServerAddress(serverAddress)) }
        return .normal
    }
}

enum GameQuickPlay {
    static func supports(instance: GameInstance, manifest: VersionManifest) -> Bool {
        let features = ["has_quick_plays_support": true, "is_quick_play_singleplayer": true, "is_quick_play_multiplayer": true]
        let declared = (manifest.arguments?.game ?? []).flatMap { $0.values(architecture: GameInstaller.architecture(for: manifest), features: features) }
        if declared.contains(where: { $0 == "--quickPlayPath" || $0 == "--quickPlayMultiplayer" || $0 == "--quickPlaySingleplayer" }) { return true }
        if WorldQuickPlay.supports(instance: instance, manifest: manifest) { return true }
        // Minecraft moved from 1.x to year-based releases in 2026.
        return instance.gameVersion.range(of: #"^(?:2[6-9]|[3-9][0-9])\.[0-9]+(?:\.[0-9]+)?(?:-(?:pre|rc)[0-9]+)?$"#, options: .regularExpression) != nil
    }
    static func supportsLegacyServer(_ version: String) -> Bool {
        version.range(of: #"^1\.(?:[7-9]|1[0-9])(?:\.[0-9]+)?(?:-(?:pre|rc)[0-9]+)?$"#, options: .regularExpression) != nil
    }
    static func applying(_ destination: LaunchDestination, arguments: [String], logging: URL?, gameDirectory: URL) -> [String] {
        var replaced: Set<String> = ["--quickPlayPath"]
        if destination != .normal { replaced.formUnion(["--quickPlaySingleplayer", "--quickPlayMultiplayer", "--quickPlayRealms", "--server", "--port", "--gameDir"]) }
        var result: [String] = [], index = 0
        while index < arguments.count {
            let value = arguments[index], key = String(value.split(separator: "=", maxSplits: 1).first ?? "")
            if replaced.contains(key) {
                index += 1
                if !value.contains("="), index < arguments.count, !arguments[index].hasPrefix("--") { index += 1 }
            } else { result.append(value); index += 1 }
        }
        switch destination {
        case .normal: break
        case .world(let folder): result += ["--quickPlaySingleplayer", folder]
        case .server(let address):
            if logging != nil { result += ["--quickPlayMultiplayer", address.authority] }
            else { result += ["--server", address.host, "--port", String(address.port)] }
        }
        if destination != .normal { result += ["--gameDir", gameDirectory.path] }
        if let logging { result += ["--quickPlayPath", logging.path] }
        return result
    }
}
