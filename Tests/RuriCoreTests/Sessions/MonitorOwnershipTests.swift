import Foundation
import Testing
@testable import RuriCore
@testable import RuriMonitorRuntime

struct MonitorOwnershipTests {
    @Test @MainActor func handoffKeepsInstanceReservedAndAllowsOnlyDesignatedMonitor() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let first = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        #expect(GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        #expect(throws: (any Error).self) { try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline") }
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        try first.handoff(to: identity)
        #expect(throws: (any Error).self) { try first.setJava("stale preparation callback") }
        #expect(try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: first.record.id).java == nil)
        #expect(!GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        // The persistent handoff record closes the gap between releasing the
        // GUI lease and acquiring the monitor's lease.
        #expect(throws: (any Error).self) { try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline") }
        let wrong = ProcessIdentity(pid: identity.pid, startSeconds: 0, startMicroseconds: 0)
        #expect(throws: (any Error).self) { try MonitorSessionRecorder(resuming: first.record.id, instanceID: instance.id, paths: paths, monitor: wrong) }
        let resumed = try MonitorSessionRecorder(resuming: first.record.id, instanceID: instance.id, paths: paths, monitor: identity)
        #expect(GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        try resumed.fail(RuriError.message("controlled failure"), cancelled: false)
        #expect(!GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        let next = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try next.fail(CancellationError(), cancelled: true)
        #expect(try GameSessionStore.list(paths: paths, instanceID: instance.id).count == 2)
    }
    @Test(arguments: [GameRunDirectory.isolated, .shared]) @MainActor
    func designatedMonitorResumesWithoutLoadingLauncherState(mode: GameRunDirectory) throws {
        let (base, original) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: base.root) }
        var instance = original; instance.runDirectory = mode
        let paths = base.including(instance)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let preparation = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let frozen = SessionLocationSnapshot(paths: paths, instanceID: instance.id)
        try preparation.handoff(to: identity)
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: instance.id) }
        // An unrelated settings writer cannot change the frozen runtime location.
        try Data("not a launcher settings document".utf8).write(to: paths.state)
        var lease: SessionRunLease? = try .resume(paths: frozen, instanceID: instance.id, sessionID: preparation.record.id, monitor: identity)
        #expect(lease != nil)
        #expect(throws: (any Error).self) { try SessionRunFileLease.instance(at: paths.instance(instance.id)) }
        var record = preparation.record; record.state = .failed; record.revision += 1
        try GameHistoryStore.record(record, paths: frozen)
        try lease?.clearReservation(session: record)
        lease = nil
        try FileManager.default.removeItem(at: paths.state)
        let next = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        withExtendedLifetime(next) {}
    }

    @Test @MainActor func missingHandoffWrongIdentityAndPendingTransactionsPreventAdoption() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = GameDirectory(id: UUID(), name: "Repository", url: root.appendingPathComponent("repository"), createdAt: Date(), layout: .minecraft)
        try FileManager.default.createDirectory(at: repository.url, withIntermediateDirectories: true)
        try JSONEncoder().encode(GameDirectory.Marker(schema: 1, id: repository.id, layout: .minecraft))
            .write(to: repository.url.appendingPathComponent(GameDirectory.markerName))
        var instance = GameInstance(name: "Shared repository", gameVersion: "1.21.1")
        instance.directoryID = repository.id; instance.repositoryVersionID = "local-version"; instance.runDirectory = .shared
        let paths = LauncherPaths(root: root.appendingPathComponent("launcher"), directories: [repository]).including(instance)
        try paths.prepare()
        func markPending(_ operation: SessionOperation) throws -> URL {
            let marker = operation.url(paths: paths, instanceID: instance.id)
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            switch operation {
            case .copyPublication, .sharedDirectoryChange, .modpackUpdate: try Data().write(to: marker)
            default: try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
            }
            return marker
        }
        withExtendedLifetime(try GameRunLease.acquire(paths: paths, instanceID: instance.id)) {}
        // Exercise Core's real entry point, including its recovery-aware guards.
        // Adding a barrier must protect both new launches and monitor adoption.
        for operation in SessionOperation.allCases {
            let marker = try markPending(operation)
            #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: instance.id) }
            try FileManager.default.removeItem(at: marker)
        }
        // A directory of staged update files is not yet a committed journal.
        #expect(!ModpackUpdateStore.hasPending(paths: paths, instanceID: instance.id))
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let frozen = SessionLocationSnapshot(paths: paths, instanceID: instance.id)
        #expect(throws: (any Error).self) { try SessionRunLease.resume(paths: frozen, instanceID: instance.id, sessionID: recorder.record.id, monitor: identity) }
        try recorder.handoff(to: identity)
        let wrong = ProcessIdentity(pid: identity.pid, startSeconds: 0, startMicroseconds: 0)
        #expect(throws: (any Error).self) { try SessionRunLease.resume(paths: frozen, instanceID: instance.id, sessionID: recorder.record.id, monitor: wrong) }
        for operation in SessionOperation.allCases {
            let marker = try markPending(operation)
            #expect(throws: (any Error).self) { try SessionRunLease.resume(paths: frozen, instanceID: instance.id, sessionID: recorder.record.id, monitor: identity) }
            try FileManager.default.removeItem(at: marker)
        }
        #expect(try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) == recorder.record)
        withExtendedLifetime(try SessionRunLease.resume(paths: frozen, instanceID: instance.id, sessionID: recorder.record.id, monitor: identity)) {}
    }
}
