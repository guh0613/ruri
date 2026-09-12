import RuriLocalization
import Foundation

public struct InstanceMoveProgress: Sendable {
    public enum Phase: String, Sendable { case verifying, copying, publishing, committed, retiring, deleting }
    public let phase: Phase
    public var bytesCopied: Int64 = 0
    public var totalBytes: Int64 = 0
    public var progress: InstallProgress {
        switch phase {
        case .verifying: .init(Messages.CoreInstanceMoveProgress.progressText1)
        case .copying: .init(Messages.CoreInstanceMoveProgress.progressText2, completed: Int(bytesCopied), total: Int(totalBytes))
        case .publishing: .init(Messages.CoreInstanceMoveProgress.progressText3, completed: Int(bytesCopied), total: Int(totalBytes))
        case .committed: .init(Messages.CoreInstanceMoveProgress.progressText4)
        case .retiring: .init(Messages.CoreInstanceMoveProgress.progressText5)
        case .deleting: .init(Messages.CoreInstanceMoveProgress.progressText6)
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
    public init(message: String, preservedFiles: [URL], cancelled: Bool) { self.message = message; self.preservedFiles = preservedFiles; self.cancelled = cancelled }
    public var errorDescription: String? { message }
}
