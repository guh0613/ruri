import Foundation
import Testing
@testable import RuriCore

struct MonitorTransportTests {
    private func nextOutput(_ observation: GameMonitorObservation, containing value: String) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                for try await update in observation.updates {
                    if let output = update.output, output.text.contains(value) { return output.text }
                }
                throw POSIXError(.ECONNRESET)
            }
            group.addTask { try await Task.sleep(for: .seconds(8)); throw POSIXError(.ETIMEDOUT) }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
    @Test(.timeLimit(.minutes(1))) @MainActor func privateSocketStreamsRedactedOutputWithoutPreviewFilesAndReconnects() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'ready private-token\\n'; exec /bin/sleep 30"],
                              directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"])
        try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: ["private-token"], helper: TestPaths.monitorExecutable)
        func load() throws -> GameSession { try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) }
        defer { if let record = try? load(), !record.state.isFinished { try? GameMonitorClient.requestStop(paths: paths, record: record) } }
        let running = try load()
        let endpoint = try #require(running.controlEndpoint)
        #expect(endpoint.utf8.count < 104)
        for _ in 0..<2 {
            let observation = GameMonitorObservation(session: running, includeOutput: true)
            let text = try await nextOutput(observation, containing: "ready")
            observation.cancel()
            #expect(text.contains("<redacted>") && !text.contains("private-token"))
        }
        #expect(!FileManager.default.fileExists(atPath: recorder.directory.appendingPathComponent("log-preview.log").path))
        #expect(!FileManager.default.fileExists(atPath: recorder.directory.appendingPathComponent("log-request.json").path))
        #expect(try GameHistoryStore.load(paths: paths, sessionID: running.id)?.controlEndpoint == endpoint)
        try GameMonitorClient.requestStop(paths: paths, record: try load())
        let ended = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: running.id)
        #expect(ended.state == .stopped && ended.timing?.quality == .complete)
        #expect(!FileManager.default.fileExists(atPath: endpoint))
    }
}
