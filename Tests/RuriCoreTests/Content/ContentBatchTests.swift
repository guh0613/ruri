import Foundation
import Testing
@testable import RuriCore

struct ContentBatchTests {
    @Test func dependencyGroupCanToggleAndBeRemovedTogether() async throws {
        let fixture = ContentManagerTests(), (paths, _, manager) = try fixture.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var resource = try fixture.plan(paths, project: "resources", version: "1", file: "resources.zip", text: "resources", dependencies: ["api"])
        resource.record.kind = .resourcepack
        try await manager.install([
            fixture.plan(paths, project: "api", version: "1", file: "api.jar", text: "api"),
            fixture.plan(paths, project: "mod", version: "1", file: "mod.jar", text: "mod", dependencies: ["api"]), resource
        ])
        let files = try await manager.scan(.mod) + manager.scan(.resourcepack)
        let api = try #require(files.first { $0.managed?.projectID == "api" })
        await #expect(throws: (any Error).self) { try await manager.setEnabled(false, files: [api]) }
        #expect(try await manager.records().allSatisfy(\.enabled))
        try await manager.setEnabled(false, files: Array(files.reversed()))
        #expect(try await manager.records().allSatisfy { !$0.enabled })
        let disabled = try await manager.scan(.mod) + manager.scan(.resourcepack)
        try await manager.setEnabled(true, files: disabled)
        #expect(try await manager.records().allSatisfy(\.enabled))
        let enabled = try await manager.scan(.mod) + manager.scan(.resourcepack)
        let base = try #require(enabled.first { $0.managed?.projectID == "api" })
        await #expect(throws: (any Error).self) { try await manager.remove([base]) }
        let trashed = try #require(await manager.remove(enabled))
        defer { try? FileManager.default.removeItem(at: trashed) }
        #expect(try await manager.records().isEmpty)
        #expect(try await manager.scan(.mod).isEmpty)
        #expect(try Data(contentsOf: trashed.appendingPathComponent("mods/api.jar")) == Data("api".utf8))
        #expect(try Data(contentsOf: trashed.appendingPathComponent("resourcepacks/resources.zip")) == Data("resources".utf8))
    }
    @Test func batchValidatesEveryTargetBeforeChangingAnyFile() async throws {
        let fixture = ContentManagerTests(), (paths, id, manager) = try fixture.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try await manager.install([
            fixture.plan(paths, project: "a", version: "1", file: "a.jar", text: "a"),
            fixture.plan(paths, project: "b", version: "1", file: "b.jar", text: "b")
        ])
        let selected = try await manager.scan(.mod), root = paths.game(id).appendingPathComponent("mods")
        try Data("collision".utf8).write(to: root.appendingPathComponent("b.jar.disabled"))
        await #expect(throws: (any Error).self) { try await manager.setEnabled(false, files: selected) }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.jar").path))
        #expect(try await manager.records().allSatisfy(\.enabled))
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.jar.disabled"))
        try Data("changed since selection".utf8).write(to: root.appendingPathComponent("b.jar"))
        await #expect(throws: (any Error).self) { try await manager.remove(selected) }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.jar").path))
        #expect(try await manager.records().count == 2)
    }
}
