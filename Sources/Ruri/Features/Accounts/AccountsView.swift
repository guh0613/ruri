import SwiftUI
import AppKit
import RuriCore

/// Signed-in accounts as a grouped settings-style list.
struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var relogin: Account?
    @State private var appearanceAccount: Account?
    var body: some View {
        Form {
            Section {
                if model.state.accounts.isEmpty {
                    Label("还没有账号。添加 Microsoft 账号或外置认证账号登录正版服务器，也可以使用离线账号游玩本地世界。", systemImage: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary).padding(.vertical, 4)
                }
                ForEach(model.state.accounts) { account in accountRow(account) }
            } header: {
                Text("账号")
            } footer: {
                Text("登录凭据保存在 macOS 钥匙串中。外置认证用于对应认证站支持的服务器；离线身份不支持正版验证服务器。")
            }
        }
        .formStyle(.grouped)
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { model.showAccount = true } label: { Label("添加账号", systemImage: "plus") }.help("添加账号").disabled(model.busy || model.readOnly) } }
        .sheet(item: $relogin) { ExternalAccountReloginView(account: $0) }
        .sheet(item: $appearanceAccount) { AccountAppearanceView(account: $0) }
    }
    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.square.fill").font(.system(size: 30)).foregroundStyle(Theme.accent).symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.username).font(.headline)
                Text(account.kindLabel).font(.caption).foregroundStyle(.secondary)
                if let login = account.externalLogin { Text(login.server.url.absoluteString).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Spacer()
            if model.state.activeAccountID == account.id { TagPill(text: "当前使用") }
            else { Button("使用此账号") { model.state.activeAccountID = account.id; model.save() }.disabled(model.readOnly) }
            Menu {
                if account.kind != .offline { Button("皮肤与披风…", systemImage: "tshirt") { appearanceAccount = account } }
                if account.kind == .external {
                    Button("刷新登录状态", systemImage: "arrow.clockwise") { run { try await model.refreshExternal(account) } }
                    Button("重新登录", systemImage: "key") { relogin = account }
                    Button("退出登录并移除", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { run { try await model.logoutExternal(account) } }
                    Divider()
                }
                Button("从 Ruri 移除账号", systemImage: "trash", role: .destructive) { model.removeAccount(account) }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.busy || model.readOnly)
        }
        .padding(.vertical, 4)
    }
    private func run(_ operation: @escaping @MainActor @Sendable () async throws -> Void) {
        model.perform("更新账号") { _ in try await operation() }
    }
}
