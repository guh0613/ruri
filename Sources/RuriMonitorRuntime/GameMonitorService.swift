import Darwin
import Foundation
import RuriLocalization

public enum GameMonitorService {
    @MainActor public static func runFromStandardInput() async -> Int32 {
        // A monitor belongs to the game, not to the terminal or GUI that started it.
        _ = setsid(); _ = signal(SIGHUP, SIG_IGN)
        var request: MonitorLaunchRequest?
        do {
            var data = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= 2_097_152 else { throw RuriError.message(Messages.CoreGameMonitor.requestInfoTooLarge) }
            }
            let decoded = try JSONDecoder().decode(MonitorLaunchRequest.self, from: data)
            request = decoded
            guard decoded.version == MonitorLaunchRequest.currentVersion, decoded.plan.executable.isFileURL,
                  decoded.monitor == ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier) else { throw RuriError.message(Messages.CoreGameMonitor.invalidMonitorRequest) }
            let context = LocalizationContext(language: decoded.language, region: decoded.region ?? Locale.current.identifier)
            return try await LocalizationContext.$current.withValue(context) {
                let paths = try validatedPaths(decoded)
                guard decoded.plan.directory.resolvingSymlinksInPath() == paths.game(decoded.instanceID).resolvingSymlinksInPath() else { throw RuriError.message(Messages.CoreGameMonitor.sessionDirectoryMismatch) }
                let recorder = try MonitorSessionRecorder(resuming: decoded.sessionID, instanceID: decoded.instanceID, paths: paths, monitor: decoded.monitor)
                recorder.addSecrets(decoded.secrets + decoded.plan.environmentRedactions)
                try recorder.configureLogging(debug: decoded.plan.debugLogging == true)
                return try await GameSessionCoordinator(plan: decoded.plan, recorder: recorder, paths: paths).run()
            }
        } catch {
            if let request {
                LocalizationContext.$current.withValue(LocalizationContext(language: request.language, region: request.region ?? Locale.current.identifier)) {
                    try? recordUnstartedFailure(request, error: error)
                }
            }
            return 1
        }
    }
    @MainActor private static func recordUnstartedFailure(_ request: MonitorLaunchRequest, error: any Error) throws {
        guard request.monitor.pid == ProcessInfo.processInfo.processIdentifier, request.monitor.isAlive else { return }
        let paths = try validatedPaths(request)
        var record = try GameSessionStore.load(paths: paths, instanceID: request.instanceID, sessionID: request.sessionID)
        guard !record.state.isFinished, record.processID == nil, record.monitorIdentity == request.monitor else { return }
        var redactor = GameLogRedactor(); redactor.addSecrets(request.secrets + request.plan.environmentRedactions)
        record.revision = (record.revision) + 1; record.finalSnapshot = true; record.controlEndpoint = nil
        record.state = .failed; record.failure = redactor.redact(String(error.localizedDescription.prefix(32768))); record.updatedAt = Date()
        record.failureMessage = (error as? RuriError)?.localizedMessage?.recorded(limit: 32768, redact: redactor.redact)
        try GameHistoryStore.record(record, paths: paths)
    }
    static func validatedPaths(_ request: MonitorLaunchRequest) throws -> SessionLocationSnapshot {
        guard request.version == MonitorLaunchRequest.currentVersion else { throw RuriError.message(Messages.CoreGameMonitor.invalidMonitorRequest) }
        return try request.storage.validated(for: request.instanceID)
    }
}
