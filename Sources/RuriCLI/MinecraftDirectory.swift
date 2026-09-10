import Foundation
import RuriCore

extension CLI {
    static func scanMinecraft(_ args: [String]) async throws {
        guard (2...3).contains(args.count), args.count == 2 || args[2] == "--json" else {
            throw RuriError.message("用法：ruri-cli scan-minecraft <Minecraft目录|版本目录|版本JSON> [--json]。只读取已有版本及游戏数据位置。")
        }
        let catalog = try await MinecraftDirectoryReader().scan(URL(fileURLWithPath: args[1]))
        if args.count == 3 {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(MinecraftDirectoryOutput(catalog)), as: UTF8.self))
            return
        }
        print("\(catalog.directory.path)\n发现 \(catalog.versions.count) 个版本")
        for version in catalog.versions {
            print("\n\(version.id) · \(version.subtitle)")
            if let issue = version.issue { print("无法读取：\(issue)"); continue }
            for location in version.gameLocations {
                print("\(location.title)\(location.id == version.suggestedLocationID ? "（原配置）" : "")：\(location.directory.path)")
                print(location.available ? (location.contents.isEmpty ? "未发现常见游戏数据" : location.contents.joined(separator: "、")) : "位置不可用")
            }
            for warning in version.warnings { print("提示：\(warning)") }
        }
    }
}

/// Explicit projection: never serialize source documents, account databases,
/// JVM arguments or other contents of another launcher's configuration.
private struct MinecraftDirectoryOutput: Encodable {
    let directory: String
    let selectedVersionID: String?
    let versions: [Version]
    struct Version: Encodable {
        let id: String
        let gameVersion: String?
        let components: [String: String]
        let locations: [Location]
        let suggestedLocation: String?
        let warnings: [String]
        let issue: String?
    }
    struct Location: Encodable {
        let path: String
        let title: String
        let available: Bool
        let contents: [String]
    }
    init(_ catalog: MinecraftDirectoryCatalog) {
        directory = catalog.directory.path; selectedVersionID = catalog.selectedVersionID
        versions = catalog.versions.map { version in
            .init(id: version.id, gameVersion: version.gameVersion,
                  components: Dictionary(uniqueKeysWithValues: version.components.map { ($0.name, $0.version) }),
                  locations: version.gameLocations.map { .init(path: $0.directory.path, title: $0.title, available: $0.available, contents: $0.contents) },
                  suggestedLocation: version.suggestedLocationID, warnings: version.warnings, issue: version.issue)
        }
    }
}
