import Foundation
import Darwin

@MainActor enum GameCommandRunner {
    static func run(_ command: String, phase: GameCommandResult.Phase, plan: LaunchPlan, timeoutSeconds: Int, exit: GameExit? = nil,
                    recorder: GameSessionRecorder, shouldStop: @escaping @MainActor () -> Bool) async -> GameCommandResult {
        let started = Date(), clock = ContinuousClock.now, process = GameProcess()
        var cancelled = false, timedOut = false
        var watcher: Task<Void, Never>?
        var environment = plan.environment
        environment.removeValue(forKey: "RURI_EXIT_CODE"); environment.removeValue(forKey: "RURI_EXIT_REASON")
        if let exit { environment["RURI_EXIT_CODE"] = String(exit.shellStatus); environment["RURI_EXIT_REASON"] = exit.reason.rawValue }
        let commandPlan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command], directory: plan.directory, environment: environment, customEnvironmentNames: plan.customEnvironmentNames)
        let result: GameCommandResult
        do {
            try recorder.transition(phase == .before ? .beforeCommand : .afterCommand)
            if shouldStop() {
                let cancelled = GameCommandResult(phase: phase, startedAt: started, endedAt: Date(), status: nil, cancelled: true, timedOut: false, error: nil)
                try recorder.commandFinished(cancelled)
                return cancelled
            }
            let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
                do {
                    try process.start(plan: commandPlan) { line in try? recorder.append("[\(phase.title)] " + line) } onExit: { result in
                        continuation.resume(returning: result.shellStatus)
                    }
                    if let pid = process.processIdentifier { try? recorder.commandStarted(processID: pid) }
                    let commandIdentity = recorder.record.commandIdentity
                    watcher = Task { @MainActor in
                        while process.isRunning {
                            let timeout = clock.duration(to: .now) >= .seconds(timeoutSeconds)
                            if shouldStop() || timeout {
                                cancelled = !timeout; timedOut = timeout
                                let identities = commandIdentity.map(ownedTree) ?? []
                                signal(identities, value: SIGTERM)
                                // A command may ignore TERM or leave a child behind.
                                // Recheck recorded process identities before escalation.
                                try? await Task.sleep(for: .seconds(2))
                                signal(identities, value: SIGKILL)
                                return
                            }
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                    }
                } catch { continuation.resume(throwing: error) }
            }
            await watcher?.value
            result = GameCommandResult(phase: phase, startedAt: started, endedAt: Date(), status: status, cancelled: cancelled, timedOut: timedOut, error: nil)
        } catch {
            watcher?.cancel()
            result = GameCommandResult(phase: phase, startedAt: started, endedAt: Date(), status: nil, cancelled: false, timedOut: false, error: recorder.redacted(error.localizedDescription))
        }
        try? recorder.commandFinished(result)
        return result
    }

    private static func ownedTree(_ root: ProcessIdentity) -> [ProcessIdentity] {
        guard root.isAlive else { return [] }
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [root] }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var parents: [Int32: [(Int32, ProcessIdentity)]] = [:]
        for pid in pids.prefix(max(0, Int(found))) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                  info.pbi_uid == getuid() else { continue }
            let identity = ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
            parents[Int32(info.pbi_ppid), default: []].append((pid, identity))
        }
        var result = [root], index = 0
        while index < result.count && result.count < 4096 {
            for (_, identity) in parents[result[index].pid] ?? [] where !result.contains(identity) { result.append(identity) }
            index += 1
        }
        return result.reversed()
    }
    private static func signal(_ identities: [ProcessIdentity], value: Int32) {
        for identity in identities where identity.isAlive { _ = Darwin.kill(identity.pid, value) }
    }
}
