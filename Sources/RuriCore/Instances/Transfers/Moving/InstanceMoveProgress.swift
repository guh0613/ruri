import Foundation

public struct InstanceMoveProgress: Sendable {
    public enum Phase: String, Sendable { case verifying, copying, publishing, committed, retiring, deleting }
    public let phase: Phase
    public var bytesCopied: Int64 = 0
    public var totalBytes: Int64 = 0
    public var progress: InstallProgress {
        switch phase {
        case .verifying: .init("正在校验实例文件…")
        case .copying: .init("正在复制实例文件…", completed: Int(bytesCopied), total: Int(totalBytes))
        case .publishing: .init("正在写入目标文件夹…", completed: Int(bytesCopied), total: Int(totalBytes))
        case .committed: .init("实例已移动，正在核对原文件…")
        case .retiring: .init("正在整理原实例文件…")
        case .deleting: .init("正在清理已核验的原文件…")
        }
    }
}
public struct InstanceMoveResult: Sendable {
    public let state: PersistentState
    public let preservedFiles: [URL]
    public let warning: String?
}
public struct InstanceMoveRecovery: Identifiable, Sendable {
    public let id: UUID
    public let instance: GameInstance
    public let source: URL
    public let destination: URL
    public let workspace: URL
    public let retiredSource: URL?
    public let committed: Bool
}
public struct InstanceMoveFailure: LocalizedError, Sendable {
    public let message: String
    public let preservedFiles: [URL]
    public let cancelled: Bool
    public var errorDescription: String? { message }
}
