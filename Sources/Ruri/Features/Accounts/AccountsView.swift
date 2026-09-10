import SwiftUI
import AppKit
import RuriCore

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var relogin: Account?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { SectionHeading(title: "以你的身份出发", subtitle: "在多个玩家身份之间轻松切换。"); Spacer(); Button("添加账号", systemImage: "plus") { model.showAccount = true }.buttonStyle(.borderedProminent) }
                if model.state.accounts.isEmpty { EmptyPanel(symbol: "person.crop.circle.badge.plus", title: "欢迎，冒险家", detail: "添加 Microsoft 账号，或使用离线身份游玩本地世界。") }
                ForEach(model.state.accounts) { account in
                    Surface {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.square.fill").font(.system(size: 42)).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account.username).font(.headline)
                                Text(account.kindLabel).font(.caption).foregroundStyle(.secondary)
                                if let login = account.externalLogin { Text(login.server.url.absoluteString).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                            }
                            Spacer()
                            if model.state.activeAccountID == account.id { TagPill(text: "当前使用") }
                            else { Button("使用此账号") { model.state.activeAccountID = account.id; model.save() } }
                            Menu {
                                if account.kind == .external {
                                    Button("刷新登录状态") { run { try await model.refreshExternal(account) } }
                                    Button("重新登录") { relogin = account }
                                    Button("退出登录并移除", role: .destructive) { run { try await model.logoutExternal(account) } }
                                    Divider()
                                }
                                Button("从 Ruri 移除账号", role: .destructive) { model.removeAccount(account) }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().disabled(model.busy || model.readOnly)
                        }
                    }
                }
                Surface {
                    Label("登录凭据保存在 macOS 钥匙串中。外置认证用于对应认证站支持的服务器；离线身份不支持正版验证服务器。", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(30)
        }.sheet(item: $relogin) { ExternalAccountReloginView(account: $0) }
    }
    private func run(_ operation: @escaping @MainActor @Sendable () async throws -> Void) {
        model.perform("更新账号") { _ in try await operation() }
    }
}
