import RuriLocalization
import Foundation
import CryptoKit

public struct Account: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case offline, microsoft, external }
    public var id: UUID
    public var kind: Kind
    public var username: String
    public var uuid: String
    public var externalLogin: ExternalAccountLogin?
    public var kindLabel: String {
        switch kind {
        case .offline: Messages.CoreAccount.kindLabelText1.localized
        case .microsoft: Messages.CoreAccount.kindLabelText2.localized
        case .external: Messages.CoreAccount.externalServer(externalLogin?.server.name ?? Messages.CoreAccount.kindLabelText4.localized).localized
        }
    }
    public init(username: String) throws {
        guard username.range(of: "^[A-Za-z0-9_]{3,16}$", options: .regularExpression) != nil else {
            throw RuriError.message(Messages.CoreAccount.kindLabelText5)
        }
        self.id = UUID(); self.kind = .offline; self.username = username
        var bytes = Array(Insecure.MD5.hash(data: Data("OfflinePlayer:\(username)".utf8)))
        bytes[6] = (bytes[6] & 0x0f) | 0x30; bytes[8] = (bytes[8] & 0x3f) | 0x80
        uuid = bytes.map { String(format: "%02x", $0) }.joined()
    }
    public init(id: UUID = UUID(), username: String, uuid: String, kind: Kind) {
        self.id = id; self.username = username; self.uuid = uuid; self.kind = kind
    }
}
