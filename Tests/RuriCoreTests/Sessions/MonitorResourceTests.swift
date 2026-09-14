import Foundation
import Testing
@testable import RuriCore

struct MonitorResourceTests {
    @MainActor private func waitFor(_ condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while try !condition() {
            guard ContinuousClock.now < deadline else { throw RuriError.message("Monitor resource fixture timed out") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test(arguments: [false, true]) @MainActor func normalRunsOnlyKeepConsoleOutputInDebugMode(debug: Bool) async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let script = #"mkdir -p logs; printf 'native log\n' > logs/latest.log; i=0; while [ $i -lt 5000 ]; do printf 'line:%s private-token\n' "$i"; i=$((i+1)); done; printf 'last private-token'"#
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"], debugLogging: debug)
        try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: ["private-token"], helper: TestPaths.monitorExecutable)
        let record = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        let log = try GameSessionStore.logTail(paths: paths, session: record)
        #expect(record.state == .succeeded && record.debugLogging == debug)
        #expect(!log.contains("private-token"))
        if debug { #expect(log.contains("line:0 <redacted>") && log.contains("last <redacted>")) }
        else {
            #expect(!log.contains("line:") && log.utf8.count < 2048 && record.events.count == 1)
            #expect(record.evidence.isEmpty && !FileManager.default.fileExists(atPath: recorder.directory.appendingPathComponent("reports").path))
        }
    }

    @Test @MainActor func failedRunSavesOnlyBoundedTailAndCurrentReports() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let script = #"i=0; while [ $i -lt 30000 ]; do printf 'line:%s private-token\n' "$i"; i=$((i+1)); done; mkdir -p logs; printf 'native failure\n' > logs/latest.log; printf 'final private-token\n'; exit 7"#
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"])
        try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: ["private-token"], helper: TestPaths.monitorExecutable)
        let record = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        let log = try GameSessionStore.logTail(paths: paths, session: record)
        #expect(record.state == .failed && record.exit?.status == 7)
        #expect(log.contains("line:29999 <redacted>") && log.contains("final <redacted>") && !log.contains("line:0 "))
        #expect(!log.contains("private-token") && log.utf8.count < 300_000)
        #expect(record.evidence.map(\.name) == ["latest.log"])
    }

    @Test @MainActor func visiblePreviewIsOnDemandAndStopRemainsResponsive() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'ready private-token\\n'; exec /bin/sleep 30"], directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"])
        try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: ["private-token"], helper: TestPaths.monitorExecutable)
        func load() throws -> GameSession { try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) }
        defer { if let record = try? load(), !record.state.isFinished { try? GameMonitorClient.requestStop(paths: paths, record: record) } }
        try await waitFor { try load().state == .running }
        let running = try load(), file = recorder.directory.appendingPathComponent("log-preview.log")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try !GameSessionStore.logTail(paths: paths, session: running).contains("ready"))
        try GameMonitorClient.requestLogSnapshot(paths: paths, session: running)
        try await waitFor { (try? String(contentsOf: file, encoding: .utf8).contains("ready <redacted>")) == true }
        let exported = paths.root.appendingPathComponent("exported.log")
        try GameSessionStore.exportLog(paths: paths, session: running, to: exported)
        #expect(try String(contentsOf: exported, encoding: .utf8).contains("ready <redacted>"))
        let start = ContinuousClock.now
        try GameMonitorClient.requestStop(paths: paths, record: running)
        let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: running.id)
        #expect(finished.state == .stopped && start.duration(to: .now) < .seconds(2))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test(arguments: ["printf 'ordinary ERROR message\\n'", "printf 'Unable to launch\\n'", "mkdir -p crash-reports; printf 'failure' > crash-reports/crash-current.txt"]) @MainActor func zeroExitChecksConcreteCrashEvidence(script: String) async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"])
        try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: TestPaths.monitorExecutable)
        let record = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        let failed = !script.contains("ordinary")
        #expect(record.exit?.status == 0 && record.state == (failed ? .failed : .succeeded))
        #expect(record.exit?.shellStatus == (failed ? 1 : 0))
    }

    @Test @MainActor func retentionBoundsHistoryWithoutLosingPlaytime() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        for _ in 0..<14 {
            let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
            try recorder.finish(exit: .init(status: 0, reason: .exit, processID: 123, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false, durationSeconds: 10))
        }
        #expect(try GameSessionStore.list(paths: paths, instanceID: instance.id).count == 10)
        #expect(try GamePlaytimeStore.load(paths: paths, instanceID: instance.id)?.total == 140)
        #expect(try GamePlaytimeStore.load(paths: paths, instanceID: instance.id)?.sessions.count == 10)
        for _ in 0..<5 {
            let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
            try recorder.fail(RuriError.message("fixture failure"), cancelled: false)
        }
        let records = try GameSessionStore.list(paths: paths, instanceID: instance.id)
        #expect(records.filter { $0.state == .failed }.count == 3 && records.count == 13)
        #expect(try GamePlaytimeStore.load(paths: paths, instanceID: instance.id)?.total == 140)
    }

    @Test @MainActor func largeNativeLogPreservesTheFailureTailWithinReportBudget() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let logs = paths.game(instance.id).appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let text = "old first line\n" + String(repeating: "ordinary line\n", count: 250_000) + "final failure\n"
        try Data(text.utf8).write(to: logs.appendingPathComponent("latest.log"))
        try recorder.finish(exit: .init(status: 1, reason: .exit, processID: 123, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false))
        let evidence = try #require(recorder.record.evidence.first)
        let saved = try String(contentsOf: recorder.directory.appendingPathComponent(evidence.relativePath), encoding: .utf8)
        #expect(evidence.truncated && saved.contains("final failure") && !saved.contains("old first line"))
        #expect(saved.utf8.count < 2_100_000)
    }
}
