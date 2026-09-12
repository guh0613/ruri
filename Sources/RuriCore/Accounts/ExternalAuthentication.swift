import RuriLocalization
import Foundation

public struct ExternalAuthServer: Codable, Equatable, Sendable {
    public let url: URL
    public let name: String

    public static func address(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "authlib-injector:yggdrasil-server:"
        if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)).removingPercentEncoding ?? "" }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw RuriError.message(Messages.CoreExternalAuthentication.hostText1)
        }
        components.scheme = "https"; components.host = host.lowercased()
        if components.port == 443 { components.port = nil }
        if components.path.isEmpty { components.path = "/" }
        guard let url = components.url else { throw RuriError.message(Messages.CoreExternalAuthentication.urlText1) }
        return url
    }
}

public struct ExternalAccountLogin: Codable, Equatable, Sendable {
    public let server: ExternalAuthServer
    public let username: String
}

public struct ExternalAuthProfile: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    var normalizedID: String { id.replacingOccurrences(of: "-", with: "").lowercased() }
    func validate() throws {
        guard normalizedID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              !name.isEmpty, name.utf8.count <= 256, !name.contains("\0") else {
            throw RuriError.message(Messages.CoreExternalAuthentication.validateText1)
        }
    }
}

public struct ExternalAuthUser: Codable, Sendable {
    public struct Property: Codable, Sendable { public let name: String; public let value: String }
    public let id: String
    public let properties: [Property]?
    public var propertiesJSON: String {
        var values: [String: [String]] = [:]
        for property in properties ?? [] { values[property.name, default: []].append(property.value) }
        return (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "{}"
    }
}

public struct ExternalAccountCredentials: Codable, Sendable {
    public let accessToken: String
    public let clientToken: String
    public let user: ExternalAuthUser?
}

public struct ExternalAuthSession: Decodable, Sendable {
    public let accessToken: String
    public let clientToken: String
    public let availableProfiles: [ExternalAuthProfile]?
    public let selectedProfile: ExternalAuthProfile?
    public let user: ExternalAuthUser?
    public var credentials: ExternalAccountCredentials { .init(accessToken: accessToken, clientToken: clientToken, user: user) }

    public func account(server: ExternalAuthServer, username: String, replacing existing: Account? = nil) throws -> Account {
        guard let profile = selectedProfile else { throw RuriError.message(Messages.CoreExternalAuthentication.profileText1) }
        try profile.validate()
        if let existing {
            guard existing.kind == .external, existing.externalLogin?.server.url == server.url,
                  existing.externalLogin?.username == username, existing.uuid == profile.normalizedID else {
                throw RuriError.message(Messages.CoreExternalAuthentication.existingText1)
            }
        }
        var result = Account(id: existing?.id ?? UUID(), username: profile.name, uuid: profile.normalizedID, kind: .external)
        result.externalLogin = .init(server: server, username: username)
        return result
    }
}

public struct ExternalAuthMetadata: Sendable {
    public let server: ExternalAuthServer
    public let data: Data
}

/// Credentials only go to the API root already presented in the login form.
/// Discovery GETs may redirect over HTTPS; credential POSTs never redirect.
final class AccountRequestRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let allowed = task.originalRequest?.httpMethod == "GET" && task.originalRequest?.value(forHTTPHeaderField: "Authorization") == nil
            && request.url.flatMap { try? ExternalAuthServer.address($0.absoluteString) } != nil
        completionHandler(allowed ? request : nil)
    }
}

public struct ExternalAuthentication: Sendable {
    private let session: URLSession
    private let redirects = AccountRequestRedirects()
    public init(session: URLSession = .shared) { self.session = session }

    public func discover(_ address: String) async throws -> ExternalAuthMetadata {
        let url = try ExternalAuthServer.address(address)
        var (data, response) = try await request(url)
        var resolved = try ExternalAuthServer.address(response.url?.absoluteString ?? url.absoluteString)
        if let location = response.value(forHTTPHeaderField: "X-Authlib-Injector-API-Location"),
           let indicated = URL(string: location, relativeTo: resolved)?.absoluteURL {
            let target = try ExternalAuthServer.address(indicated.absoluteString)
            if target != resolved {
                (data, response) = try await request(target)
                resolved = try ExternalAuthServer.address(response.url?.absoluteString ?? target.absoluteString)
            }
        }
        try requireSuccess(response.statusCode)
        return try metadata(data, url: resolved)
    }

    public func metadata(for server: ExternalAuthServer) async throws -> ExternalAuthMetadata {
        let url = try ExternalAuthServer.address(server.url.absoluteString)
        let (data, response) = try await request(url)
        try requireSuccess(response.statusCode)
        // Do not silently migrate a saved identity to a different authentication service.
        guard response.url == url else { throw RuriError.message(Messages.CoreExternalAuthentication.urlText2) }
        return try metadata(data, url: url)
    }

    public func login(server: ExternalAuthServer, username: String, password: String) async throws -> ExternalAuthSession {
        guard !username.isEmpty, !password.isEmpty else { throw RuriError.message(Messages.CoreExternalAuthentication.loginText1) }
        let client = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let result = try await exchange(server, action: "authenticate", body: ["username": username, "password": password,
            "clientToken": client, "requestUser": true, "agent": ["name": "Minecraft", "version": 1]], clientToken: client)
        guard result.selectedProfile != nil || result.availableProfiles?.isEmpty == false else {
            throw RuriError.message(Messages.CoreExternalAuthentication.resultText1)
        }
        return result
    }

    public func select(_ profile: ExternalAuthProfile, from pending: ExternalAuthSession, server: ExternalAuthServer) async throws -> ExternalAuthSession {
        guard pending.selectedProfile == nil, pending.availableProfiles?.contains(profile) == true else { throw RuriError.message(Messages.CoreExternalAuthentication.selectText1) }
        let result = try await exchange(server, action: "refresh", body: ["accessToken": pending.accessToken,
            "clientToken": pending.clientToken, "requestUser": true, "selectedProfile": ["id": profile.id, "name": profile.name]], clientToken: pending.clientToken)
        guard result.selectedProfile?.normalizedID == profile.normalizedID else { throw RuriError.message(Messages.CoreExternalAuthentication.resultText2) }
        return result
    }

    public func refresh(account: Account, credentials: ExternalAccountCredentials, force: Bool = false) async throws -> (Account, ExternalAccountCredentials) {
        guard let login = account.externalLogin, account.kind == .external else { throw RuriError.message(Messages.CoreExternalAuthentication.loginText2) }
        let tokens: [String: Any] = ["accessToken": credentials.accessToken, "clientToken": credentials.clientToken]
        if !force {
            let (_, response) = try await request(endpoint(login.server, "validate"), body: tokens)
            if response.statusCode == 204 { return (account, credentials) }
            guard [401, 403].contains(response.statusCode) else { try requireSuccess(response.statusCode); throw RuriError.message(Messages.CoreExternalAuthentication.tokensText1) }
        }
        var body = tokens; body["requestUser"] = true
        let result = try await exchange(login.server, action: "refresh", body: body, clientToken: credentials.clientToken)
        return (try result.account(server: login.server, username: login.username, replacing: account), result.credentials)
    }

    public func invalidate(server: ExternalAuthServer, credentials: ExternalAccountCredentials) async throws {
        let (_, response) = try await request(endpoint(server, "invalidate"), body: ["accessToken": credentials.accessToken, "clientToken": credentials.clientToken])
        try requireSuccess(response.statusCode)
    }

    private func endpoint(_ server: ExternalAuthServer, _ action: String) throws -> URL {
        try ExternalAuthServer.address(server.url.absoluteString).appendingPathComponent("authserver/" + action)
    }
    private func exchange(_ server: ExternalAuthServer, action: String, body: [String: Any], clientToken: String) async throws -> ExternalAuthSession {
        let (data, response) = try await request(endpoint(server, action), body: body)
        try requireSuccess(response.statusCode)
        let value = try JSONDecoder().decode(ExternalAuthSession.self, from: data)
        guard value.clientToken == clientToken, !value.accessToken.isEmpty, !value.accessToken.contains("\0") else { throw RuriError.message(Messages.CoreExternalAuthentication.valueText1) }
        for profile in (value.availableProfiles ?? []) + [value.selectedProfile].compactMap({ $0 }) { try profile.validate() }
        return value
    }
    private func metadata(_ data: Data, url: URL) throws -> ExternalAuthMetadata {
        struct Metadata: Decodable {
            struct Meta: Decodable { let serverName: String? }
            let meta: Meta?; let skinDomains: [String]; let signaturePublickey: String
        }
        guard let value = try? JSONDecoder().decode(Metadata.self, from: data) else { throw RuriError.message(Messages.CoreExternalAuthentication.valueText2) }
        guard value.signaturePublickey.contains("-----BEGIN PUBLIC KEY-----") else { throw RuriError.message(Messages.CoreExternalAuthentication.valueText3) }
        var root = url
        if !root.absoluteString.hasSuffix("/") { root.appendPathComponent("") }
        let name = value.meta?.serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .init(server: .init(url: root, name: name.isEmpty ? (root.host ?? Messages.CoreExternalAuthentication.nameText1.localized) : String(name.prefix(120))), data: data)
    }
    private func requireSuccess(_ status: Int) throws {
        guard (200..<300).contains(status) else {
            if [401, 403].contains(status) { throw RuriError.message(Messages.CoreExternalAuthentication.requireSuccessText1) }
            throw RuriError.message(Messages.CoreExternalAuthentication.requireSuccessText2(String(describing: status)))
        }
    }
    private func request(_ url: URL, body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpShouldHandleCookies = false
        request.setValue("Ruri/0.1", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request, delegate: redirects)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, data.count <= 65_536 else { throw RuriError.message(Messages.CoreExternalAuthentication.responseText1) }
        return (data, response)
    }
}
