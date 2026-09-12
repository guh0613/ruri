import SwiftUI
import AppKit
import RuriCore

struct AddAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "microsoft"
    @State private var username = ""
    @State private var code: DeviceCode?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(title: "添加玩家账号", subtitle: "登录一次，随时回到你的世界。")
            Picker("账号类型", selection: $mode) { Text("Microsoft").tag("microsoft"); Text("外置认证").tag("external"); Text("离线账号").tag("offline") }.pickerStyle(.segmented).disabled(task != nil)
            if mode == "external" {
                ExternalAccountForm()
            } else if mode == "offline" {
                TextField("玩家名", text: $username).textFieldStyle(.roundedBorder)
                Text("使用 3–16 位英文字母、数字或下划线。离线账号用于单人游戏与允许离线模式的服务器。").font(.callout).foregroundStyle(.secondary)
            } else if model.state.settings.effectiveMicrosoftClientID.isEmpty {
                Label("先配置 Microsoft 应用", systemImage: "key.horizontal").font(.headline)
                Text("Ruri 需要自己的 Microsoft Client ID 才能发起登录。请在设置中填写已启用公共客户端与 Xbox 登录的应用 ID。").font(.callout).foregroundStyle(.secondary)
                Button("前往设置") { model.page = .settings; dismiss() }
            } else if let code {
                Text("在浏览器中登录 Microsoft，并输入此代码：").foregroundStyle(.secondary)
                HStack { Text(code.user_code).font(.system(size: 31, weight: .bold, design: .monospaced)).textSelection(.enabled); Spacer(); Button("复制代码") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code.user_code, forType: .string) } }
                Button("打开 Microsoft 登录页面", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(code.verification_uri) }
                HStack { ProgressView().controlSize(.small); Text("等待浏览器中完成登录…").font(.callout).foregroundStyle(.secondary) }
            } else {
                Label("使用你拥有 Minecraft Java 版的 Microsoft 账号登录。", systemImage: "person.badge.key").font(.callout).foregroundStyle(.secondary)
                if task != nil { ProgressView("正在请求登录代码…") }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer(); Button("取消") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                if mode == "offline" {
                    Button("添加账号") { do { try model.addOffline(username); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(username.isEmpty)
                } else if mode == "microsoft", code == nil {
                    Button("继续登录") { login() }.buttonStyle(.borderedProminent).disabled(task != nil || model.state.settings.effectiveMicrosoftClientID.isEmpty)
                }
            }
        }.padding(30).frame(width: 500).onDisappear { task?.cancel() }
    }
    private func login() {
        error = nil
        task = Task {
            do {
                let auth = MicrosoftAuth(clientID: model.state.settings.effectiveMicrosoftClientID)
                let code = try await auth.begin(); self.code = code
                NSWorkspace.shared.open(code.verification_uri)
                let (account, credentials) = try await auth.finish(code)
                try Task.checkCancellation(); try model.addMicrosoft(account, credentials: credentials); dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; code = nil } }
            task = nil
        }
    }
}
