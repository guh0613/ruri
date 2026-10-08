import Foundation
import Testing
import Darwin
@testable import RuriCore

struct CacheMaintenanceTests {
    /// Clone counts need APFS, which the temporary directory uses on macOS.
    static var tracksClones: Bool {
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-clone-probe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: probe) }
        guard (try? Data("probe".utf8).write(to: probe)) != nil else { return false }
        return CacheMaintenance.cloneInfo(probe.path).id != nil
    }
    private func fixture() throws -> (root: URL, cache: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-cache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return (root, root.appendingPathComponent("cache"))
    }
    @discardableResult private func file(_ path: String, in root: URL, size: Int = 64 * 1024) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<size).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        return url
    }
    /// Cache copies are clones, as the downloader makes them.
    @discardableResult private func clone(_ source: URL, to path: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }
    private func allocated(_ url: URL) -> Int64 { CacheMaintenance.entry(url)?.allocated ?? 0 }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @Test(.enabled(if: tracksClones)) func onlyDownloadsNoGameFileSharesAreRemoved() throws {
        let (root, cache) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let shared = try file("objects/aa/shared", in: cache)
        let mod = try clone(shared, to: "game/mods/shared.jar", in: root)
        let orphan = try file("objects/bb/orphan", in: cache)
        // A landing copy and its SHA-1 entry that no instance uses any more.
        let landing = try file("curseforge/1/unused.jar", in: cache)
        let stored = try clone(landing, to: "objects/cc/unused", in: cache)
        // A landing copy of a file an instance still uses.
        let used = try file("modrinth/v/used.jar", in: cache)
        let usedEntry = try clone(used, to: "objects/dd/used", in: cache)
        try clone(used, to: "game/mods/used.jar", in: root)
        let archive = try file("pack-fixture.mrpack", in: cache)
        let expected = allocated(orphan) + allocated(landing) + allocated(archive)

        let maintenance = CacheMaintenance(cache: cache, now: Date().addingTimeInterval(1), recent: 0)
        let survey = maintenance.survey()
        #expect(survey.bytes == expected)
        #expect(maintenance.clean() == survey)
        #expect(exists(shared) && exists(mod) && exists(usedEntry))
        #expect(!exists(orphan) && !exists(landing) && !exists(stored) && !exists(archive))
        // The redundant landing copy goes; the SHA-1 entry serves later downloads.
        #expect(!exists(used))
        #expect(!exists(landing.deletingLastPathComponent()))
        #expect(maintenance.survey().bytes == 0)
    }

    @Test func recentFilesAndHeldLocksStay() async throws {
        let (root, cache) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let orphan = try file("objects/bb/orphan", in: cache)
        let target = cache.appendingPathComponent("modrinth/v/pending.jar")
        let lock = try await DownloadFileLock.acquire(for: target)
        let lockFile = try #require(try FileManager.default.contentsOfDirectory(at: target.deletingLastPathComponent().appendingPathComponent(".ruri-partials"), includingPropertiesForKeys: nil).first)
        let maintenance = CacheMaintenance(cache: cache)
        #expect(maintenance.clean().files == 0)
        #expect(exists(orphan) && exists(lockFile))
        close(lock)
        maintenance.prune()
        #expect(!exists(lockFile))
    }

    @Test func startupRemovesInterruptedWorkAndArchivesOnly() throws {
        let (root, cache) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let orphan = try file("objects/bb/orphan", in: cache)
        let workspace = try file("transfer-fixture/unpacked/mods/a.jar", in: cache).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let loaderWork = try file("loader-work/instance/forge-1/libraries/a.jar", in: cache)
        let partial = try file("curseforge/1/.ruri-partials/fixture.part", in: cache)
        let update = try file("pack-updates/modrinth/1/pack.mrpack", in: cache)
        let metadata = try file("versions.json", in: cache)
        CacheMaintenance(cache: cache, now: Date().addingTimeInterval(2 * 86_400)).removeLeftovers()
        #expect(exists(orphan) && exists(metadata))
        #expect(!exists(workspace) && !exists(loaderWork) && !exists(partial) && !exists(update))
        #expect(exists(cache.appendingPathComponent("loader-work")))
    }

    @Test func archivesOutsideTheCacheBelongToTheUser() throws {
        let (root, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        let own = try file("Downloads/pack.mrpack", in: root)
        let downloaded = try file("cache/pack-1.mrpack", in: root)
        CacheMaintenance.discardArchive(own, paths: paths)
        CacheMaintenance.discardArchive(downloaded, paths: paths)
        #expect(exists(own) && !exists(downloaded))
    }
}
