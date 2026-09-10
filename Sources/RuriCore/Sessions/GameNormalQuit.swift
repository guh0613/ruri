import Foundation
import AppKit

struct GameNormalQuitRequest: Codable {
    let version: Int
    let id: UUID
    let sessionID: UUID
    let requestedAt: Date
}

public struct GameNormalQuitAttempt: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let requestedAt: Date
    public let processedAt: Date
    public let accepted: Bool
    public var explanation: String {
        accepted ? "系统已接收正常退出请求，正在等待游戏处理；Ruri 会继续采集日志，不会自动升级为终止进程。"
                 : "没有成功发送正常退出请求。游戏窗口可能尚未就绪，或不支持这条退出路径；请返回游戏，通过游戏菜单退出。"
    }
}

public enum NativeGameQuit {
    /// An accepted request is not an exit acknowledgement. Cocoa/GLFW may
    /// decline or defer it; only the process owner records the eventual exit.
    @MainActor public static func request(_ identity: ProcessIdentity) -> Bool {
        guard identity.isAlive,
              let application = NSRunningApplication(processIdentifier: identity.pid), !application.isTerminated, application.activationPolicy != .prohibited,
              identity.isAlive else { return false }
        return application.terminate()
    }
}

extension GameMonitorClient {
    @discardableResult public static func requestNormalQuit(paths: LauncherPaths, record: GameSession) throws -> UUID {
        let current = try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        guard !current.state.isFinished, current.monitorIdentity == record.monitorIdentity,
              current.gameIdentity == record.gameIdentity, current.monitorIdentity?.isAlive == true,
              current.gameIdentity?.isAlive == true else { throw RuriError.message("游戏或监控状态已经变化，暂时无法请求正常退出。") }
        guard current.nativeQuitSupported == true else { throw RuriError.message("本次启动未启用应用退出请求，请返回游戏，通过游戏菜单退出。") }
        let directory = try GameSessionStore.directory(paths: paths, instanceID: current.instanceID, sessionID: current.id)
        let request = GameNormalQuitRequest(version: 1, id: UUID(), sessionID: current.id, requestedAt: Date())
        let file = try LauncherPaths.safePath("quit-request.json", within: directory)
        try JSONEncoder().encode(request).write(to: file, options: .atomic)
        try? recordEvent(.normalQuitRequested, paths: paths, session: current)
        return request.id
    }
    static func normalQuitRequest(directory: URL, session: GameSession) -> GameNormalQuitRequest? {
        guard let file = try? LauncherPaths.safePath("quit-request.json", within: directory),
              let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              attributes.isRegularFile == true, (attributes.fileSize ?? .max) <= 2048,
              let data = try? Data(contentsOf: file), let request = try? JSONDecoder().decode(GameNormalQuitRequest.self, from: data),
              request.version == 1, request.sessionID == session.id, request.requestedAt >= session.createdAt,
              request.requestedAt <= Date().addingTimeInterval(5) else { return nil }
        return request
    }
}
