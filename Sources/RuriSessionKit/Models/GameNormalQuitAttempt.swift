import Foundation
import RuriLocalization

public struct GameNormalQuitAttempt: Codable, Equatable, Sendable {
    package init(requestID: UUID, requestedAt: Date, processedAt: Date, accepted: Bool) {
        self.requestID = requestID
        self.requestedAt = requestedAt
        self.processedAt = processedAt
        self.accepted = accepted
    }

    public let requestID: UUID
    public let requestedAt: Date
    public let processedAt: Date
    public let accepted: Bool
    public var explanation: String { explanationMessage.localized }
    public var explanationMessage: LocalizedMessage {
        accepted ? Messages.CoreGameNormalQuit.normalExitRequestPending
                 : Messages.CoreGameNormalQuit.normalExitRequestFailed
    }
}
