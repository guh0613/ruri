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
        case .offline: Messages.CoreAccount.offlineAccount.localized
        case .microsoft: Messages.CoreAccount.microsoftAccount.localized
        case .external: Messages.CoreAccount.externalServer(externalLogin?.server.name ?? Messages.CoreAccount.externalAuth.localized).localized
        }
    }
    public init(username: String) throws {
        guard username.range(of: "^[A-Za-z0-9_]{3,16}$", options: .regularExpression) != nil else {
            throw RuriError.message(Messages.CoreAccount.playerNameRule)
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

extension Account {
    public func hasSameIdentity(as other: Account) -> Bool {
        kind == other.kind && uuid.replacingOccurrences(of: "-", with: "").lowercased() == other.uuid.replacingOccurrences(of: "-", with: "").lowercased()
            && externalLogin?.server.url == other.externalLogin?.server.url && externalLogin?.username == other.externalLogin?.username
    }
    /// A reauthentication must prove the same identity before replacing secrets.
    public func reauthenticated(with updated: Account) throws -> Account {
        guard kind != .offline, hasSameIdentity(as: updated) else {
            throw RuriError.message(Messages.AccountCenter.wrongLoginAccount)
        }
        var result = updated; result.id = id; result.uuid = uuid
        return result
    }
}
