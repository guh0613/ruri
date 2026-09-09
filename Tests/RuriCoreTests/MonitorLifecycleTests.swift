import Foundation
import Testing
@testable import RuriCore

struct MonitorLifecycleTests {
    @MainActor private func waitFor(_ condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while try !condition() {
            guard Date() < deadline else { throw RuriError.message("监控生命周期验证超时。") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    @Test(.timeLimit(.minutes(1))) @MainActor func monitorOutlivesParentAndAcceptsReconnectedStopWithoutPersistingCredentials() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = repository.appendingPathComponent(".build/validation/out/Products/Debug/ruri-monitor")
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.transition(.starting)
        let parent = Process(), input = Pipe(), output = Pipe()
        let trigger = paths.root.appendingPathComponent("parent-exit")
        parent.executableURL = URL(fileURLWithPath: "/bin/sh")
        parent.arguments = ["-c", #"exec 3<&0; "$1" run <&3 >/dev/null 2>/dev/null & printf '%s\n' "$!"; while [ ! -f "$2" ]; do sleep 0.05; done"#, "ruri-monitor-test", helper.path, trigger.path]
        parent.standardInput = input; parent.standardOutput = output; parent.standardError = FileHandle.nullDevice
        try parent.run()
        defer {
            try? input.fileHandleForWriting.close()
            FileManager.default.createFile(atPath: trigger.path, contents: nil)
        }
        let pidText = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(Int32(pidText))
        let identity = try #require(ProcessIdentity.read(pid))
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"),
                              arguments: ["-c", #"trap 'printf "game-stopped\n"; exit 0' TERM; printf 'fixture-access-secret\n'; while :; do sleep 0.05; done"#],
                              directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"])
        try recorder.handoff(to: identity)
        let request = MonitorLaunchRequest(version: 1, root: paths.root, instanceID: instance.id, sessionID: recorder.record.id, monitor: identity, plan: plan, secrets: ["fixture-access-secret", "fixture-refresh-secret"])
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request)); try input.fileHandleForWriting.close()
        func load() throws -> GameSession { try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) }
        defer { if let record = try? load() { try? GameMonitorClient.requestStop(paths: paths, record: record) } }
        try await waitFor { try load().state == .running }
        FileManager.default.createFile(atPath: trigger.path, contents: nil)
        try await waitFor { !parent.isRunning }
        let reconnected = try load()
        #expect(reconnected.monitorIdentity?.isAlive == true && reconnected.gameIdentity?.isAlive == true)
        #expect(reconnected.ownerPID == identity.pid)
        #expect(GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        #expect(throws: (any Error).self) { try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline") }
        try GameMonitorClient.requestStop(paths: paths, record: reconnected)
        let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(finished.state == .stopped && finished.exit?.stopRequested == true)
        #expect(finished.monitorIdentity?.isAlive == false && finished.gameIdentity?.isAlive == false)
        #expect(!GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        let log = try GameSessionStore.logTail(paths: paths, session: finished)
        #expect(log.contains("<redacted>") && log.contains("game-stopped") && log.contains("Ruri 结束请求：是"))
        try assertNoCredentials(in: paths.instance(instance.id))
    }
    private func assertNoCredentials(in directory: URL) throws {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            #expect(!text.contains("fixture-access-secret") && !text.contains("fixture-refresh-secret"))
        }
    }
}
