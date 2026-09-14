import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct InstallerJavaRuntimeTests {
    private func runtime(_ major: Int) -> JavaRuntime {
        .init(path: "/java/\(major)", version: String(major), major: major, architecture: JavaRuntime.hostArchitecture, vendor: "Test")
    }

    @Test func existingCompatibleJavaDoesNotRequestADownload() async throws {
        let java = runtime(21)
        let selected = try await InstallerJavaRuntime.$request.withValue({ _, _ in
            Issue.record("An existing compatible Java must not prompt")
            throw CancellationError()
        }) {
            try await InstallerJavaRuntime.resolve(minimumMajor: 8, component: "Forge", from: [java])
        }
        #expect(selected == java)
    }

    @Test func missingJavaWithoutAnInteractiveResolverDoesNotDownload() async {
        await #expect(throws: (any Error).self) {
            try await InstallerJavaRuntime.resolve(minimumMajor: 17, component: "Forge", from: [])
        }
    }

    @Test func cancellationPropagatesAndResolutionIsScopedToTheOperation() async throws {
        await #expect(throws: CancellationError.self) {
            try await InstallerJavaRuntime.$request.withValue({ major, component in
                #expect(major == 17 && component == "NeoForge")
                throw CancellationError()
            }) {
                try await Task { try await InstallerJavaRuntime.resolve(minimumMajor: 17, component: "NeoForge", from: []) }.value
            }
        }
        #expect(InstallerJavaRuntime.request == nil)
        let java = runtime(21)
        let selected = try await InstallerJavaRuntime.$request.withValue({ _, _ in java }) {
            try await InstallerJavaRuntime.resolve(minimumMajor: 17, component: "Forge", from: [])
        }
        #expect(selected == java)
        let incompatible = runtime(8)
        await #expect(throws: (any Error).self) {
            try await InstallerJavaRuntime.$request.withValue({ _, _ in incompatible }) {
                try await InstallerJavaRuntime.resolve(minimumMajor: 17, component: "Forge", from: [])
            }
        }
    }

    @Test func toolBytecodeDeterminesMinimumWithoutCountingOptionalJavaOverlays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func jar(_ name: String, classes: [(String, UInt8)]) throws -> URL {
            let file = root.appendingPathComponent(name)
            let archive = try Archive(url: file, accessMode: .create)
            for (path, major) in classes {
                let data = Data([0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, major + 44])
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { position, count in
                    data.subdata(in: Int(position)..<(Int(position) + count))
                }
            }
            return file
        }
        let installer = try jar("installer.jar", classes: [("Main.class", 8), ("module-info.class", 9), ("META-INF/versions/22/FastPath.class", 22)])
        let processor = try jar("processor.jar", classes: [("Processor.class", 17)])
        #expect(try JavaBytecode.minimumMajor(in: [installer]) == 8)
        #expect(try JavaBytecode.minimumMajor(in: [installer, processor]) == 17)
    }
}
