import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct LocalModMetadataTests {
    func archive(_ entries: [String: Data], at url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), provider: { position, count in
                data.subdata(in: Int(position)..<min(Int(position) + count, data.count))
            })
        }
    }
    @Test func forgeMetadataHandlesMultilineTOMLAndManifestVersion() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jar")
        defer { try? FileManager.default.removeItem(at: url) }
        let toml = #"""
        modLoader = "javafml"
        loaderVersion = "[47,)"
        logoFile = "logo.png"
        [[mods]]
        modId = "example"
        displayName = "Example # One"
        version = "${file.jarVersion}"
        authors = "Alice, Bob"
        displayURL = "https://example.test"
        description = '''First line.
        Second line with 'quotes' and # symbols.'''
        [[dependencies.example]]
        modId = "forge"
        mandatory = true
        """#
        try archive(["META-INF/mods.toml": Data(toml.utf8), "META-INF/MANIFEST.MF": Data("Manifest-Version: 1.0\r\nImplementation-Version: 1.2.\r\n 3\r\n\r\n".utf8), "logo.png": Data([1, 2, 3])], at: url)
        let info = try #require(LocalModMetadata.read(url))
        #expect(info.id == "example" && info.name == "Example # One" && info.version == "1.2.3")
        #expect(info.loaders == ["Forge"] && info.authors == ["Alice, Bob"])
        #expect(info.summary?.contains("Second line with 'quotes' and # symbols.") == true)
        #expect(LocalModMetadata.iconData(at: url, path: try #require(info.iconPath)) == Data([1, 2, 3]))
    }
    @Test func neoforgeAndOldForgeHaveRealNamesAndVersions() throws {
        for (path, text, loader) in [
            ("META-INF/neoforge.mods.toml", "[[mods]]\nmodId='example'\ndisplayName='Example'\nversion='2.0'", "NeoForge"),
            ("mcmod.info", #"{"modList":[{"modid":"example","name":"Example","version":"2.0","authorList":["Alice"],"url":"javascript:bad"}]}"#, "Forge")
        ] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jar.disabled")
            defer { try? FileManager.default.removeItem(at: url) }
            try archive([path: Data(text.utf8)], at: url)
            let info = try #require(LocalModMetadata.read(url))
            #expect(info.id == "example" && info.name == "Example" && info.version == "2.0" && info.loaders == [loader])
            #expect(info.homepage == nil)
        }
    }
    @Test func fabricAndQuiltMetadataAndIconsAreReadWithoutExtracting() throws {
        for (path, text, loader) in [
            ("fabric.mod.json", #"{"id":"example","name":"Example","version":"1","authors":["Alice",{"name":"Bob"}],"icon":{"32":"small.png","128":"large.png"}}"#, "Fabric"),
            ("quilt.mod.json", #"{"quilt_loader":{"id":"example","version":"1","metadata":{"name":"Example","contributors":{"Alice":"Owner","Bob":"Artist"},"icon":"large.png"}}}"#, "Quilt")
        ] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jar")
            defer { try? FileManager.default.removeItem(at: url) }
            try archive([path: Data(text.utf8)], at: url)
            let info = try #require(LocalModMetadata.read(url))
            #expect(info.id == "example" && info.authors == ["Alice", "Bob"] && info.iconPath == "large.png" && info.loaders == [loader])
        }
    }
    @Test func malformedAndOversizedMetadataDoesNotBreakFileListing() async throws {
        let (paths, id, manager) = try ContentManagerTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let directory = paths.game(id).appendingPathComponent("mods")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try archive(["fabric.mod.json": Data(repeating: 65, count: 1024 * 1024 + 1)], at: directory.appendingPathComponent("large.jar"))
        try archive(["META-INF/mods.toml": Data("not TOML".utf8)], at: directory.appendingPathComponent("broken.jar"))
        let files = try await manager.scan(.mod)
        #expect(files.count == 2 && files.allSatisfy { $0.metadata == nil })
    }
    @Test func nameIndexUsesIDsAndDisambiguatesExactNames() {
        let index = ModNameIndex(text: "a;1;shared;第一;First Mod;F\nb;2;shared;第二;Second Mod;S\nc;3;different;第三;Third;T")
        #expect(index.match(id: "shared", name: "Second-Mod")?.encyclopediaID == "2")
        #expect(index.match(id: "different", name: "First Mod")?.encyclopediaID == "3")
        #expect(index.match(id: nil, name: "First_Mod")?.encyclopediaID == "1")
        #expect(index.match(id: nil, name: "First Mod Extra") == nil)
        #expect(ModNameIndex.shared.match(id: "jei", name: "Just Enough Items")?.chineseName.isEmpty == false)
    }
}
