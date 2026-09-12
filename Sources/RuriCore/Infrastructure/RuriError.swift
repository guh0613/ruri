import Foundation
import RuriLocalization

public enum RuriError: LocalizedError, Sendable {
    case message(String)
    case localized(LocalizedMessage)
    public static func message(_ value: LocalizedMessage) -> Self { .localized(value) }
    public var localizedMessage: LocalizedMessage? { if case .localized(let value) = self { value } else { nil } }
    public var messageID: String? { localizedMessage?.key }
    public var errorDescription: String? {
        switch self { case .message(let text): text; case .localized(let value): value.localized }
    }
}
