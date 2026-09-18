import Foundation
import RuriLocalization

public enum RuriError: LocalizedError, Sendable {
    case message(String)
    case localized(LocalizedMessage)
    case httpResponse(statusCode: Int, host: String)
    public static func message(_ value: LocalizedMessage) -> Self { .localized(value) }
    public var localizedMessage: LocalizedMessage? {
        switch self {
        case .localized(let value): value
        case .httpResponse(let statusCode, let host): Messages.CoreNetwork.httpError(host, String(statusCode))
        case .message: nil
        }
    }
    var httpStatusCode: Int? { if case .httpResponse(let code, _) = self { code } else { nil } }
    public var messageID: String? { localizedMessage?.key }
    public var errorDescription: String? {
        switch self { case .message(let text): text; default: localizedMessage?.localized }
    }
}
