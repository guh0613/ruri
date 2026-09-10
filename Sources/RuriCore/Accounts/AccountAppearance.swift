import Foundation

public struct AccountTexture: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let url: URL
    public let active: Bool
    public let model: PlayerSkinModel
}
public struct AccountAppearance: Sendable {
    public let account: Account
    public let playerName: String
    public let skin: AccountTexture?
    public let capes: [AccountTexture]
    public let uploadable: Set<PlayerTextureKind>
    public var activeCape: AccountTexture? { capes.first(where: \.active) }
}

/// Authenticated API requests use fixed Microsoft endpoints or the account's
/// saved external API root. Image downloads never carry a login token.
public struct AccountAppearanceClient: Sendable {
    private let account: Account
    private let accessToken: String
    private let session: URLSession
    private let redirects = AccountRequestRedirects()
    public init(account: Account, accessToken: String, session: URLSession = .shared) {
        self.account = account; self.accessToken = accessToken; self.session = session
    }
    public func load() async throws -> AccountAppearance {
        switch account.kind {
        case .offline: throw RuriError.message("离线账号没有在线皮肤资料。")
        case .microsoft:
            struct Profile: Decodable {
                struct Texture: Decodable {
                    let id: String; let state: String; let url: URL; let variant: String?; let alias: String?
                    var texture: AccountTexture { .init(id: id, name: alias ?? "披风", url: url, active: state == "ACTIVE", model: variant?.lowercased() == "slim" ? .slim : .classic) }
                }
                let id: String; let name: String; let skins: [Texture]; let capes: [Texture]
            }
            let profile = try JSONDecoder().decode(Profile.self, from: await api(AuthenticationEndpoints.profile))
            try validateID(profile.id)
            return .init(account: account, playerName: profile.name, skin: profile.skins.first(where: { $0.state == "ACTIVE" })?.texture,
                         capes: profile.capes.map(\.texture), uploadable: [.skin])
        case .external:
            struct Profile: Decodable {
                struct Property: Decodable { let name: String; let value: String }
                let id: String; let name: String; let properties: [Property]?
            }
            struct Textures: Decodable {
                struct Texture: Decodable { let url: URL; let metadata: [String: String]? }
                let profileId: String?
                let textures: [String: Texture]
            }
            let profile = try JSONDecoder().decode(Profile.self, from: await api(external("sessionserver/session/minecraft/profile/" + account.uuid), authenticated: false))
            try validateID(profile.id)
            let properties = profile.properties ?? []
            let uploadable = Set((properties.first { $0.name == "uploadableTextures" }?.value ?? "").split(separator: ",").compactMap { PlayerTextureKind(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) })
            var skin: AccountTexture?, capes: [AccountTexture] = []
            if let encoded = properties.first(where: { $0.name == "textures" })?.value {
                guard let data = Data(base64Encoded: encoded) else { throw RuriError.message("认证站返回的外观信息无效。") }
                let payload = try JSONDecoder().decode(Textures.self, from: data)
                if let id = payload.profileId { try validateID(id) }
                if let texture = payload.textures["SKIN"] { skin = .init(id: "skin", name: "当前皮肤", url: texture.url, active: true, model: texture.metadata?["model"] == "slim" ? .slim : .classic) }
                if let texture = payload.textures["CAPE"] { capes = [.init(id: "cape", name: "当前披风", url: texture.url, active: true, model: .classic)] }
            }
            return .init(account: account, playerName: profile.name, skin: skin, capes: capes, uploadable: uploadable)
        }
    }

    public func upload(_ image: PlayerTextureImage, kind: PlayerTextureKind, model: PlayerSkinModel = .classic, expecting appearance: AccountAppearance) async throws {
        try validate(appearance)
        guard appearance.uploadable.contains(kind) else { throw RuriError.message("此账号不支持直接上传\(kind.title)，请到认证站管理。") }
        try image.validate(kind: kind, accountKind: account.kind, model: model)
        let boundary = "Ruri-" + UUID().uuidString
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        if kind == .skin {
            let field = account.kind == .microsoft ? "variant" : "model"
            let value = account.kind == .microsoft ? model.rawValue : model == .slim ? "slim" : ""
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"\r\n\r\n\(value)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(kind.rawValue).png\"\r\nContent-Type: image/png\r\n\r\n")
        body.append(image.png); append("\r\n--\(boundary)--\r\n")
        let url = try account.kind == .microsoft ? AuthenticationEndpoints.profile.appendingPathComponent("skins") : external("api/user/profile/\(account.uuid)/\(kind.rawValue)")
        _ = try await api(url, method: account.kind == .microsoft ? "POST" : "PUT", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
    }

    public func reset(_ kind: PlayerTextureKind, expecting appearance: AccountAppearance) async throws {
        try validate(appearance)
        if account.kind == .external, !appearance.uploadable.contains(kind) { throw RuriError.message("此认证站不支持直接修改\(kind.title)，请到认证站管理。") }
        let url = try account.kind == .microsoft ? AuthenticationEndpoints.profile.appendingPathComponent(kind == .skin ? "skins/active" : "capes/active") : external("api/user/profile/\(account.uuid)/\(kind.rawValue)")
        _ = try await api(url, method: "DELETE")
    }

    public func selectCape(_ id: String, expecting appearance: AccountAppearance) async throws {
        try validate(appearance)
        guard account.kind == .microsoft, appearance.capes.contains(where: { $0.id == id }) else { throw RuriError.message("请选择此 Microsoft 账号拥有的披风。") }
        let body = try JSONEncoder().encode(["capeId": id])
        _ = try await api(AuthenticationEndpoints.profile.appendingPathComponent("capes/active"), method: "PUT", body: body, contentType: "application/json")
    }

    public func image(for texture: AccountTexture) async throws -> PlayerTextureImage {
        var url = texture.url
        guard ["https", "http"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { throw RuriError.message("外观图片地址无效。") }
        if url.scheme == "http", url.host == "textures.minecraft.net" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!; components.scheme = "https"; url = components.url!
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request, delegate: redirects)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw RuriError.message("无法下载外观图片，请重试。") }
        try Task.checkCancellation()
        return try PlayerTextureImage(data: data)
    }

    private func validate(_ appearance: AccountAppearance) throws {
        guard account.kind != .offline, appearance.account.id == account.id, appearance.account.uuid == account.uuid,
              appearance.account.kind == account.kind, appearance.account.externalLogin == account.externalLogin else { throw RuriError.message("账号已变化，请重新打开外观管理。") }
        try validateID(account.uuid)
    }
    private func validateID(_ value: String) throws {
        let normalized = value.replacingOccurrences(of: "-", with: "").lowercased()
        guard normalized == account.uuid, normalized.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else { throw RuriError.message("外观资料与当前角色不匹配，请重新登录。") }
    }
    private func external(_ path: String) throws -> URL {
        try validateID(account.uuid)
        guard let server = account.externalLogin?.server else { throw RuriError.message("账号缺少认证服务器，请重新登录。") }
        return try ExternalAuthServer.address(server.url.absoluteString).appendingPathComponent(path)
    }
    private func api(_ url: URL, method: String = "GET", body: Data? = nil, contentType: String? = nil, authenticated: Bool = true) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = method; request.httpBody = body; request.httpShouldHandleCookies = false
        if authenticated { request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization") }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request, delegate: redirects)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw RuriError.message("外观服务响应无效。") }
        guard (200..<300).contains(status) else {
            switch status {
            case 401: throw RuriError.message("登录已失效，请重新登录账号后再试。")
            case 403: throw RuriError.message("服务器未允许此账号执行这项外观操作。")
            case 429: throw RuriError.message("操作过于频繁，请稍后再试。")
            default: throw RuriError.message("外观服务返回 HTTP \(status)，请检查图片格式或稍后重试。")
            }
        }
        guard data.count <= 262_144 else { throw RuriError.message("外观资料过大，无法读取。") }
        return data
    }
}
