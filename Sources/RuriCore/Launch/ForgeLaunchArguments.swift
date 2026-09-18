import Foundation

enum ForgeLaunchArguments {
    static func bootstrap(_ arguments: [String], manifest: VersionManifest, classpath: [String], client: URL) -> [String] {
        guard manifest.mainClass == "cpw.mods.bootstraplauncher.BootstrapLauncher" else { return arguments }
        let version = manifest.libraries.first { $0.name.hasPrefix("cpw.mods:bootstraplauncher:") }?.name.split(separator: ":").last.map(String.init)
        let matchesFullPath = version.map { MinecraftDependencyVersion.compare($0, "0.1.17") == .orderedAscending } ?? false
        return arguments.map { value in
            let prefix = "-DignoreList="
            guard value.hasPrefix(prefix) else { return value }
            let tokens = value.dropFirst(prefix.count).split(separator: ",").map(String.init)
            if matchesFullPath {
                // Early bootstraps match substrings against entire paths. A
                // directory named "asm" must not hide every transformation JAR.
                let ignored = classpath.filter { path in
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    return tokens.contains { name.contains($0) }
                }
                let paths = [client.path] + ignored.filter { $0 != client.path }
                return prefix + paths.map { path in path.contains(",") ? "/" + URL(fileURLWithPath: path).lastPathComponent : path }.joined(separator: ",")
            }
            return tokens.contains(client.lastPathComponent) ? value : value + "," + client.lastPathComponent
        }
    }
}
