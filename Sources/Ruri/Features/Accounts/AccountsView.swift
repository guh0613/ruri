import SwiftUI
import AppKit
import RuriCore

struct AccountsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { SectionHeading(title: "以你的身份出发", subtitle: "在多个玩家身份之间轻松切换。"); Spacer(); Button("添加账号", systemImage: "plus") { model.showAccount = true }.buttonStyle(.borderedProminent) }
                if model.state.accounts.isEmpty { EmptyPanel(symbol: "person.crop.circle.badge.plus", title: "欢迎，冒险家", detail: "添加 Microsoft 账号，或使用离线身份游玩本地世界。") }
                ForEach(model.state.accounts) { account in
                    Surface {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.square.fill").font(.system(size: 42)).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 6) { Text(account.username).font(.headline); Text(account.kind == .microsoft ? "Microsoft · Minecraft Java" : "离线账号 · 本地与离线服务器").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if model.state.activeAccountID == account.id { TagPill(text: "当前使用") }
                            else { Button("使用此账号") { model.state.activeAccountID = account.id; model.save() } }
                            Menu { Button("移除账号", role: .destructive) { model.removeAccount(account) } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                        }
                    }
                }
                Surface {
                    Label("Microsoft 登录凭据保存在 macOS 钥匙串中。离线身份不支持正版验证服务器。", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(30)
        }
    }
}
