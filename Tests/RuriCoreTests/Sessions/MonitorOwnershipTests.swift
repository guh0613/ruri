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
}
