import Foundation
import Testing
@testable import RuriCore

struct LaunchCommandsTests {
    @MainActor private func waitFor(_ condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while try !condition() {
            guard ContinuousClock.now < deadline else { throw RuriError.message("命令验证等待超时。") }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
    @Test @MainActor func monitorRunsBeforeWrapperAndAfterWithSeparateResultsAndRedactedOutput() async throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let game = paths.game(instance.id), recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        var commands = LaunchCommands(); commands.enabled = true
        commands.before = #"printf 'before\n' >> trace; printf '%s\n' "$RURI_HOOK_SECRET""#
        commands.after = #"test "$RURI_EXIT_CODE" = 7 && test "$RURI_EXIT_REASON" = exit || exit 90; printf 'after\n' >> trace; exit 3"#
        let wrapper = paths.root.appendingPathComponent("wrapper with spaces.sh")
        try Data("printf 'wrapper\\n' >> trace\nexec \"$@\"\n".utf8).write(to: wrapper)
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'game\\n' >> trace; exit 7"], directory: game,
                              environment: ["PATH": "/bin:/usr/bin", "RURI_HOOK_SECRET": "secret-from-hook-env"], customEnvironmentNames: ["RURI_HOOK_SECRET"],
                              commands: commands, wrapper: ["/bin/sh", wrapper.path])
        try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: TestPaths.monitorExecutable)
        let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(finished.exit?.status == 7 && finished.state == .failed)
        #expect(finished.commandResults?.map(\.status) == [0, 3])
        #expect(finished.commandIdentity == nil)
        #expect(try String(contentsOf: game.appendingPathComponent("trace"), encoding: .utf8) == "before\nwrapper\ngame\nafter\n")
        let log = try GameSessionStore.logTail(paths: paths, session: finished)
        #expect(log.contains("<redacted>") && !log.contains("secret-from-hook-env"))
        #expect(finished.title.contains("退出后命令") && !GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        commands.before = "exit 11"
        let retry = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let failedPlan = LaunchPlan(executable: plan.executable, arguments: plan.arguments, directory: game, environment: plan.environment, commands: commands)
        try await GameMonitorClient.start(plan: failedPlan, recorder: retry, paths: paths, secrets: [], helper: TestPaths.monitorExecutable)
        let failed = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: retry.record.id)
        #expect(failed.state == .failed && failed.exit == nil && failed.commandResults?.map(\.status) == [11])
        #expect(try String(contentsOf: game.appendingPathComponent("trace"), encoding: .utf8) == "before\nwrapper\ngame\nafter\n")
    }

    @Test(arguments: [true, false]) @MainActor func timeoutOrCancellationStopsCommandChildrenAndNeverStartsGame(timeout: Bool) async throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let game = paths.game(instance.id), recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        var commands = LaunchCommands(); commands.enabled = true; commands.timeoutSeconds = timeout ? 1 : 30
        commands.before = #"trap '' TERM; (trap '' TERM; exec /bin/sleep 30) & printf '%s\n' "$!" > child.pid; wait"#
        commands.after = "touch after-ran"
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "touch game-ran"], directory: game, environment: ["PATH": "/bin:/usr/bin"], commands: commands)
        try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: TestPaths.monitorExecutable)
        let childFile = game.appendingPathComponent("child.pid")
        var childPID: Int32?
        try await waitFor {
            // Redirection creates the file before printf writes its PID.
            guard let contents = try? String(contentsOf: childFile, encoding: .utf8), contents.hasSuffix("\n") else { return false }
            childPID = Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
            return childPID != nil
        }
        let pid = try #require(childPID)
        // Other main-actor tests may delay this read until the independent
        // monitor has already timed out and reaped the fixture child.
        let child = ProcessIdentity.read(pid)
        #expect(timeout || child != nil)
        if !timeout {
            let current = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
            try GameMonitorClient.requestStop(paths: paths, record: current)
        }
        let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(finished.exit == nil && finished.processID == nil)
        #expect(finished.state == (timeout ? .failed : .cancelled))
        #expect(finished.commandResults?.first?.timedOut == timeout)
        #expect(finished.commandResults?.first?.cancelled == !timeout)
        #expect(child?.isAlive != true)
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("game-ran").path))
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("after-ran").path))
    }

    @Test @MainActor func afterCommandKeepsRealExitAndLeaseUntilItFinishes() async throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        var commands = LaunchCommands(); commands.enabled = true; commands.after = "touch after-started; exec /bin/sleep 30"
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 0"], directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"], commands: commands)
        try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: TestPaths.monitorExecutable)
        func load() throws -> GameSession { try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) }
        try await waitFor { try load().stage == .afterCommand && load().commandIdentity != nil }
        let waiting = try load()
        #expect(waiting.exit?.status == 0 && !waiting.state.isFinished)
        #expect(GameRunLease.isHeld(paths: paths, instanceID: instance.id))
        try GameMonitorClient.requestStop(paths: paths, record: waiting)
        let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(finished.exit?.status == 0 && finished.state == .succeeded)
        #expect(finished.commandResults?.last?.cancelled == true)
        // A stale update cannot undo an authoritative completed history row.
        var interrupted = finished; interrupted.state = .running; interrupted.stage = .afterCommand
        interrupted.commandIdentity = finished.gameIdentity; interrupted.commandResults = []
        try GameHistoryStore.record(interrupted, paths: paths)
        let restored = try load()
        #expect(restored.exit == finished.exit && restored.state == .succeeded)
        #expect(restored.commandResults == finished.commandResults)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: interrupted) }
    }

    @Test func inheritanceSnapshotsAndImportedCommandsRemainExplicit() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var commands = LaunchCommands(); commands.enabled = true; commands.before = "printf '%s\\n' \"$RURI_GAME_DIRECTORY\""; commands.wrapper = #"/usr/bin/env "RURI_NAME=${RURI_INSTANCE_NAME}""#
        var defaults = AppSettings(); defaults.defaultLaunchCommands = commands
        var instance = GameInstance(name: "House $NAME with spaces", gameVersion: "1.0"); instance.launchOverrides = .init()
        let snapshot = try instance.launchSnapshot(defaults: defaults)
        #expect(snapshot.launchCommands == commands)
        let wrapper = try commands.resolveWrapper(environment: ["RURI_INSTANCE_NAME": instance.name], directory: paths.root)
        #expect(wrapper == ["/usr/bin/env", "RURI_NAME=House $NAME with spaces"])
        var state = PersistentState(); state.settings = defaults; state.instances = [instance]
        try StateStore.save(state, to: paths)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let transfer = InstanceTransfer(paths: paths), archive = paths.cache.appendingPathComponent("commands.zip")
        try await transfer.export(instance, to: archive)
        let pack = try await transfer.prepare(archive)
        #expect(pack.instance.launchCommands?.before == commands.before)
        #expect(pack.instance.resolvedLaunchSettings(defaults: defaults).commands.enabled == false)
        await transfer.discard(pack)
        let mmc = paths.cache.appendingPathComponent("mmc")
        try FileManager.default.createDirectory(at: mmc.appendingPathComponent(".minecraft"), withIntermediateDirectories: true)
        try Data(#"{"formatVersion":1,"components":[{"uid":"net.minecraft","version":"1.0"}]}"#.utf8).write(to: mmc.appendingPathComponent("mmc-pack.json"))
        try Data("PreLaunchCommand=echo imported\nPostExitCommand=echo after\nWrapperCommand=/usr/bin/env\n".utf8).write(to: mmc.appendingPathComponent("instance.cfg"))
        let imported = try await transfer.prepare(mmc)
        #expect(imported.instance.launchCommands?.before == "echo imported")
        #expect(imported.instance.resolvedLaunchSettings(defaults: defaults).commands.enabled == false)
        await transfer.discard(imported)
        var overrides = instance.effectiveLaunchOverrides; overrides.commands = .init()
        #expect(!overrides.resolve(defaults: defaults.defaultLaunchSettings).commands.enabled)
        commands.timeoutSeconds = 0
        #expect(throws: (any Error).self) { try commands.validate() }
    }
}
