import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func scanMinecraft(_ args: [String]) async throws {
        let flags = Array(args.dropFirst(2))
        guard (2...4).contains(args.count), Set(flags).count == flags.count, Set(flags).isSubset(of: ["--json", "--resolve"]) else {
            throw RuriError.message(Messages.CLIMinecraftDirectory.flagsText1)
        }
        let reader = MinecraftDirectoryReader(), catalog = try await reader.scan(URL(fileURLWithPath: args[1]))
        var manifests: [String: MinecraftManifestOutput] = [:], issues: [String: String] = [:]
        if flags.contains("--resolve") {
            for version in catalog.versions where version.issue == nil {
                do { manifests[version.id] = try MinecraftManifestOutput(await reader.resolveManifest(version, in: catalog)) }
                catch is CancellationError { throw CancellationError() }
                catch { issues[version.id] = error.localizedDescription }
            }
        }
        if flags.contains("--json") {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(MinecraftDirectoryOutput(catalog, manifests: manifests, issues: issues)), as: UTF8.self))
            return
        }
        print(Messages.CLIMinecraftDirectory.encoderText1(String(describing: catalog.directory.path), Int64(catalog.versions.count)).localized)
        for version in catalog.versions {
            print("\n\(version.id) · \(version.subtitle)")
            if let issue = version.issue { print(Messages.CLIMinecraftDirectory.issueText1(String(describing: issue)).localized); continue }
            if let manifest = manifests[version.id] {
                print(Messages.CLIMinecraftDirectory.manifestText1(String(describing: manifest.mainClass), Int64(manifest.libraryDeclarations)).localized)
                print(Messages.CLIMinecraftDirectory.manifestText2(Int64(manifest.selectedLibraryCount), Int64(manifest.localLibraries.count), Int64(manifest.discardedLibraries.count)).localized)
                print(Messages.CLIMinecraftDirectory.manifestText3(String(describing: manifest.clientFile)).localized)
            }
            if let issue = issues[version.id] { print(Messages.CLIMinecraftDirectory.issueText2(String(describing: issue)).localized) }
            for location in version.gameLocations {
                print("\(location.title)\(location.id == version.suggestedLocationID ? Messages.CLIMinecraftDirectory.issueText3.localized : "")：\(location.directory.path)")
                print(location.available ? (location.contents.isEmpty ? Messages.CLIMinecraftDirectory.issueText4.localized : location.contents.joined(separator: "、")) : Messages.CLIMinecraftDirectory.issueText5.localized)
            }
            for warning in version.warnings { print(Messages.CLIMinecraftDirectory.issueText6(String(describing: warning)).localized) }
        }
    }
}

private struct MinecraftManifestOutput: Encodable {
    let mainClass: String
    let clientFile: String
    let libraryDeclarations: Int
    let localLibraries: [String]
    let selectedLibraryCount: Int
    let discardedLibraries: [Discarded]
    struct Discarded: Encodable { let name: String; let selectedName: String; let reason: String }
    init(_ resolution: MinecraftManifestResolution) throws {
        let selection = try resolution.selectingLibraries()
        mainClass = resolution.manifest.mainClass ?? ""
        clientFile = resolution.clientFile.path
        libraryDeclarations = resolution.libraries.count
        localLibraries = selection.libraries.filter { $0.localFile != nil }.map(\.library.name)
        selectedLibraryCount = selection.libraries.count
        discardedLibraries = selection.discarded.map { .init(name: $0.name, selectedName: $0.selectedName, reason: $0.reason.rawValue) }
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
