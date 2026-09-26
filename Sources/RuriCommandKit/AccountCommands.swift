import RuriLocalization
import Foundation
import RuriCore

extension CLIApplication {
    @MainActor static func manageAccount(_ request: CommandRequest, output: CommandOutput) async throws -> Value {
        let (state, paths, _) = try await context(request), service = AccountService(paths: paths)
        let action = request.spec.path.dropFirst().joined(separator: " ")
        switch action {
        case "list": return request.page(state.accounts.map(accountValue))
        case "selected": return .object(["id": .text(state.activeAccountID?.uuidString)])
        case "add-offline":
            let username = try request.operand()
            if request.dryRun { return .object(["dryRun": .bool(true), "account": accountValue(try Account(username: username))]) }
            return accountValue(try service.addOffline(username, activate: !request.flag("no-select")))
        case Messages.CLIInterface.t57b6d748b829.localized:
            let provider = try request.required("provider"), id = try request.string("account").map(uuid)
            if request.dryRun { return .object(["dryRun": .bool(true), "provider": .string(provider), "userParticipation": .bool(true)]) }
            if provider == "microsoft" {
                guard request.string("server") == nil, request.string("username") == nil, !request.flag("password-stdin") else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tc6b87186027e.localized) }
                return try await service.startMicrosoft(accountID: id)
            }
            guard request.flag("password-stdin") else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tb34236db1721.localized) }
            let password = String(decoding: try readInput("-", maximumBytes: 65536), as: UTF8.self).trimmingCharacters(in: .newlines)
            output.addSecrets([password])
            return try await service.startExternal(server: request.required("server"), username: request.required("username"), password: password, accountID: id)
        case Messages.CLIInterface.te307d3e2aed4.localized, Messages.CLIInterface.taf7c81279d63.localized:
            let id = try uuid(request.operand())
            if request.dryRun { return .object(["dryRun": .bool(true), "flowID": .string(id.uuidString)]) }
            if action == Messages.CLIInterface.taf7c81279d63.localized { try service.cancelLogin(id); return .object(["cancelled": .bool(true), "flowID": .string(id.uuidString)]) }
            return accountValue(try await service.completeLogin(id, profile: request.string("profile")))
        case Messages.CLIInterface.t2b2389f27e52.localized: return .object(["provider": .string("curseforge"), "custom": .bool(CurseForgeKeyStore.hasCustomKey()), "bundled": .bool(CurseForgeKeyStore.hasBundledKey)])
        case Messages.CLIInterface.t8ed19e29eef4.localized:
            guard request.flag("stdin") else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t05b618061083.localized) }
            if !request.dryRun {
                let key = String(decoding: try readInput("-", maximumBytes: 65536), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                output.addSecrets([key]); try CurseForgeKeyStore.save(key)
            }
            return .object(["provider": .string("curseforge"), "dryRun": .bool(request.dryRun)])
        case Messages.CLIInterface.tc68fadc33f5d.localized:
            if !request.dryRun { try CurseForgeKeyStore.remove() }
            return .object(["provider": .string("curseforge"), "dryRun": .bool(request.dryRun)])
        default: break
        }
        let id = try uuid(request.operand())
        if action == "remove" {
            if !request.dryRun { _ = try service.remove(id) }
            return .object(["id": .string(id.uuidString), "dryRun": .bool(request.dryRun), "removed": .bool(!request.dryRun)])
        }
        let account = try service.account(id)
        if action == "show" || request.dryRun { return .object(["account": accountValue(account), "dryRun": .bool(request.dryRun)]) }
        switch action {
        case "select": _ = try service.select(id)
        case "refresh":
            let authenticated = try await service.authenticate(id, forceRefresh: true)
            output.addSecrets(authenticated.secrets)
            return accountValue(authenticated.account)
        case "logout": _ = try await service.logout(id)
        default: throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.tfffe65605bf6.localized)
        }
        return .object(["id": .string(id.uuidString), "action": .string(action)])
    }
    static func accountValue(_ account: Account) -> Value {
        .object(["id": .string(account.id.uuidString), "kind": .string(account.kind.rawValue), "username": .string(account.username),
                 "uuid": .string(account.uuid), "server": .text(account.externalLogin?.server.url.absoluteString)])
    }
}
