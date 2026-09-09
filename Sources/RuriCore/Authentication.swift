import Foundation
import Security

public struct AccountCredentials: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var clientID: String
}

public enum CredentialStore {
    private static let service = "dev.ruri.launcher.microsoft"
    public static func save(_ credentials: AccountCredentials, for id: UUID) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw failure(status) }
        } else if update != errSecSuccess { throw failure(update) }
    }
    public static func load(for id: UUID) throws -> AccountCredentials {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return try JSONDecoder().decode(AccountCredentials.self, from: data)
    }
    public static func remove(for id: UUID) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> RuriError { .message("钥匙串访问失败（\(status)），请重新登录或检查系统授权。") }
}

public struct DeviceCode: Decodable, Sendable {
    public let device_code: String
    public let user_code: String
    public let verification_uri: URL
    public let expires_in: Int
    public let interval: Int?
}

public actor MicrosoftAuth {
    private let clientID: String
    private static let base = "https://login.microsoftonline.com/consumers/oauth2/v2.0/"
    private static let scope = "XboxLive.signin offline_access"
    public init(clientID: String) { self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    public func begin() async throws -> DeviceCode {
        guard UUID(uuidString: clientID) != nil else { throw RuriError.message("请先在设置 → 账号中填写 Ruri 的 Microsoft 应用 Client ID。") }
        let (data, status) = try await form("devicecode", values: ["client_id": clientID, "scope": Self.scope])
        guard status == 200 else { throw RuriError.message("Microsoft 拒绝了设备登录请求（HTTP \(status)）。请检查 Client ID 和公共客户端设置。") }
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }
    private struct OAuthToken: Decodable, Sendable {
        let access_token: String?; let refresh_token: String?; let error: String?
    }
    public func finish(_ code: DeviceCode) async throws -> (Account, AccountCredentials) {
        let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
        var interval = max(code.interval ?? 5, 1)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval)); try Task.checkCancellation()
            let (data, _) = try await form("token", values: ["client_id": clientID, "grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": code.device_code])
            let token = try JSONDecoder().decode(OAuthToken.self, from: data)
            if token.error == "authorization_pending" { continue }
            if token.error == "slow_down" { interval += 5; continue }
            guard let access = token.access_token, let refresh = token.refresh_token else {
                throw RuriError.message(token.error == "authorization_declined" ? "登录已取消。" : "Microsoft 登录已过期或失败，请重试。")
            }
            return try await exchange(access: access, refresh: refresh)
        }
        throw RuriError.message("设备登录代码已过期，请重新登录。")
    }
    public func refresh(_ credentials: AccountCredentials, account: Account) async throws -> (Account, AccountCredentials) {
        let (data, status) = try await form("token", values: ["client_id": credentials.clientID, "grant_type": "refresh_token", "refresh_token": credentials.refreshToken, "scope": Self.scope])
        let token = try JSONDecoder().decode(OAuthToken.self, from: data)
        guard status == 200, let access = token.access_token else { throw RuriError.message("Microsoft 登录已失效，请重新添加账号。") }
        var (updated, secrets) = try await exchange(access: access, refresh: token.refresh_token ?? credentials.refreshToken)
        updated.id = account.id; secrets.clientID = credentials.clientID
        return (updated, secrets)
    }
    private func form(_ endpoint: String, values: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: Self.base + endpoint)!)
        request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(values.sorted(by: { $0.key < $1.key }).map { key, value in "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    private func post<T: Decodable>(_ type: T.Type, url: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: URL(string: url)!); request.httpMethod = "POST"; request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let code = json["XErr"] as? Int64 {
            let explanation: String
            switch code {
            case 2148916233: explanation = "此账号尚未建立 Xbox 资料，请先登录 xbox.com 完成设置。"
            case 2148916235: explanation = "Xbox Live 在此账号所在地区不可用。"
            case 2148916236, 2148916237: explanation = "此账号需要在 Xbox 完成年龄验证。"
            case 2148916238: explanation = "此儿童账号需要加入 Microsoft 家庭并由家长授权。"
            default: explanation = "Xbox 登录失败（\(code)）。"
            }
            throw RuriError.message(explanation)
        }
        guard (200..<300).contains(status) else { throw RuriError.message("\(request.url!.host!) 登录失败（HTTP \(status)）。请检查应用是否已获 Minecraft API 访问权限。") }
        return try JSONDecoder().decode(type, from: data)
    }
    private func exchange(access: String, refresh: String) async throws -> (Account, AccountCredentials) {
        struct Xbox: Decodable { struct Claims: Decodable { let xui: [[String: String]] }; let Token: String; let DisplayClaims: Claims }
        struct Minecraft: Decodable { let access_token: String; let expires_in: Int }
        struct Entitlements: Decodable, Sendable { struct Item: Decodable, Sendable { let name: String }; let items: [Item] }
        struct Profile: Decodable, Sendable { let id: String; let name: String }
        let xbox = try await post(Xbox.self, url: "https://user.auth.xboxlive.com/user/authenticate", body: ["Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": "d=\(access)"], "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT"])
        let xsts = try await post(Xbox.self, url: "https://xsts.auth.xboxlive.com/xsts/authorize", body: ["Properties": ["SandboxId": "RETAIL", "UserTokens": [xbox.Token]], "RelyingParty": "rp://api.minecraftservices.com/", "TokenType": "JWT"])
        guard let uhs = xsts.DisplayClaims.xui.first?["uhs"], uhs == xbox.DisplayClaims.xui.first?["uhs"] else { throw RuriError.message("Xbox 账号身份校验失败。") }
        let minecraft = try await post(Minecraft.self, url: "https://api.minecraftservices.com/authentication/login_with_xbox", body: ["identityToken": "XBL3.0 x=\(uhs);\(xsts.Token)"])
        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/entitlements/mcstore")!)
        request.setValue("Bearer \(minecraft.access_token)", forHTTPHeaderField: "Authorization")
        let entitlements = try JSONDecoder().decode(Entitlements.self, from: await HTTPClient.shared.data(for: request))
        guard !entitlements.items.isEmpty else { throw RuriError.message("此 Microsoft 账号未拥有 Minecraft Java 版。") }
        request.url = URL(string: "https://api.minecraftservices.com/minecraft/profile")!
        let profile = try JSONDecoder().decode(Profile.self, from: await HTTPClient.shared.data(for: request))
        return (Account(username: profile.name, uuid: profile.id, kind: .microsoft), AccountCredentials(accessToken: minecraft.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(TimeInterval(minecraft.expires_in)), clientID: clientID))
    }
}
