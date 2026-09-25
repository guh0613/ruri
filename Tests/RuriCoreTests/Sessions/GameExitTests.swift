import Foundation
import Testing
@testable import RuriCore

struct GameExitTests {
    @Test(.timeLimit(.minutes(1))) @MainActor func outputIsDrainedBeforeExitAndDoesNotLeakIntoNextLaunch() async throws {
        let game = GameProcess()
        var lines: [String] = []
        let script = "i=0; while [ $i -lt 4000 ]; do printf 'line:%s 这是一段超过管道容量的日志\\n' \"$i\"; i=$((i+1)); done; printf 'last secret-value'"
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], directory: FileManager.default.temporaryDirectory, environment: ["PATH": "/usr/bin:/bin"])
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GameExit, any Error>) in
            do {
                try game.start(plan: plan, secrets: ["secret-value"]) { lines.append($0) } onExit: { result in
                    #expect(lines.count == 4001)
                    #expect(lines.first == "line:0 这是一段超过管道容量的日志")
                    #expect(lines.last == "last <redacted>")
                    continuation.resume(returning: result)
                }
            } catch { continuation.resume(throwing: error) }
        }
        #expect(result.succeeded)
        let next = try await run("exit 0", game: game)
        #expect(next.succeeded && lines.count == 4001)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func descendantHoldingPipeDoesNotDelayGameExit() async throws {
        let start = Date()
        let result = try await run("sleep 10 & printf 'parent finished\\n'")
        #expect(result.succeeded)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @MainActor private func run(_ script: String, game: GameProcess = GameProcess(), stopWhenReady: Bool = false) async throws -> GameExit {
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], directory: FileManager.default.temporaryDirectory, environment: ["PATH": "/usr/bin:/bin"])
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try game.start(plan: plan) { line in
                    if stopWhenReady && line == "ready" { game.stop() }
                } onExit: { result in continuation.resume(returning: result) }
            } catch { continuation.resume(throwing: error) }
        }
    }

    @Test @MainActor func signalAndExitStatusAreDistinct() async throws {
        let exited = try await run("exit 143")
        let signalled = try await run("kill -TERM $$")
        #expect(exited.reason == .exit && exited.status == 143)
        #expect(signalled.reason == .signal && signalled.status == 15)
        #expect(exited.shellStatus == 143 && signalled.shellStatus == 143)
        #expect(exited.requiresAttention && signalled.requiresAttention)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func requestedStopAndFollowingNormalLaunch() async throws {
        let game = GameProcess()
        let stopped = try await run("trap 'exit 143' TERM; printf 'ready\\n'; while :; do sleep 1; done", game: game, stopWhenReady: true)
        #expect(stopped.stopRequested && stopped.stoppedByLauncher && !stopped.requiresAttention)
        game.stop() // An already exited process must not affect the next launch.
        let normal = try await run("exit 0", game: game)
        #expect(normal.succeeded && !normal.requiresAttention && !normal.stopRequested)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func stopRequestDoesNotHideFailureDuringShutdown() async throws {
        let failed = try await run("trap 'exit 7' TERM; printf 'ready\\n'; while :; do sleep 1; done", stopWhenReady: true)
        #expect(failed.stopRequested && failed.status == 7 && failed.requiresAttention)
    }
}
