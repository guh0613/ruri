import Foundation
import RuriCore

extension CLI {
    static func scanMinecraft(_ args: [String]) async throws {
        let flags = Array(args.dropFirst(2))
        guard (2...4).contains(args.count), Set(flags).count == flags.count, Set(flags).isSubset(of: ["--json", "--resolve"]) else {
            throw RuriError.message("用法：ruri-cli scan-minecraft <Minecraft目录|版本目录|版本JSON> [--json] [--resolve]。只读取已有版本；--resolve 额外检查继承和补丁合并。")
        }
        let reader = MinecraftDirectoryReader(), catalog = try await reader.scan(URL(fileURLWithPath: args[1]))
        var manifests: [String: MinecraftManifestOutput] = [:], issues: [String: String] = [:]
        if flags.contains("--resolve") {
            for version in catalog.versions where version.issue == nil {
                do { manifests[version.id] = MinecraftManifestOutput(try await reader.resolveManifest(version, in: catalog)) }
                catch is CancellationError { throw CancellationError() }
                catch { issues[version.id] = error.localizedDescription }
            }
        }
        if flags.contains("--json") {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(MinecraftDirectoryOutput(catalog, manifests: manifests, issues: issues)), as: UTF8.self))
            return
        }
        print("\(catalog.directory.path)\n发现 \(catalog.versions.count) 个版本")
        for version in catalog.versions {
            print("\n\(version.id) · \(version.subtitle)")
            if let issue = version.issue { print("无法读取：\(issue)"); continue }
            if let manifest = manifests[version.id] {
                print("启动入口：\(manifest.mainClass) · \(manifest.libraryDeclarations) 条依赖声明，其中 \(manifest.localLibraries.count) 条使用本地文件")
                print("游戏 JAR：\(manifest.clientFile)")
            }
            if let issue = issues[version.id] { print("清单合并失败：\(issue)") }
            for location in version.gameLocations {
                print("\(location.title)\(location.id == version.suggestedLocationID ? "（原配置）" : "")：\(location.directory.path)")
                print(location.available ? (location.contents.isEmpty ? "未发现常见游戏数据" : location.contents.joined(separator: "、")) : "位置不可用")
            }
            for warning in version.warnings { print("提示：\(warning)") }
        }
    }
}

private struct MinecraftManifestOutput: Encodable {
    let mainClass: String
    let clientFile: String
    let libraryDeclarations: Int
    let localLibraries: [String]
    init(_ resolution: MinecraftManifestResolution) {
        mainClass = resolution.manifest.mainClass ?? ""
        clientFile = resolution.clientFile.path
        libraryDeclarations = resolution.libraries.count
        localLibraries = resolution.libraries.filter { $0.localFile != nil }.map(\.library.name)
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
        let manifest: MinecraftManifestOutput?
        let manifestIssue: String?
    }
    struct Location: Encodable {
        let path: String
        let title: String
        let available: Bool
        let contents: [String]
    }
    init(_ catalog: MinecraftDirectoryCatalog, manifests: [String: MinecraftManifestOutput], issues: [String: String]) {
        directory = catalog.directory.path; selectedVersionID = catalog.selectedVersionID
        versions = catalog.versions.map { version in
            .init(id: version.id, gameVersion: version.gameVersion,
                  components: Dictionary(uniqueKeysWithValues: version.components.map { ($0.name, $0.version) }),
                  locations: version.gameLocations.map { .init(path: $0.directory.path, title: $0.title, available: $0.available, contents: $0.contents) },
                  suggestedLocation: version.suggestedLocationID, warnings: version.warnings, issue: version.issue,
                  manifest: manifests[version.id], manifestIssue: issues[version.id])
        }
    }
}
