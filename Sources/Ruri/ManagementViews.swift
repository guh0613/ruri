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
            Picker("账号类型", selection: $mode) { Text("Microsoft").tag("microsoft"); Text("离线账号").tag("offline") }.pickerStyle(.segmented).disabled(task != nil)
            if mode == "offline" {
                TextField("玩家名", text: $username).textFieldStyle(.roundedBorder)
                Text("使用 3–16 位英文字母、数字或下划线。离线账号用于单人游戏与允许离线模式的服务器。").font(.callout).foregroundStyle(.secondary)
            } else if model.state.settings.microsoftClientID.isEmpty {
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
                } else if code == nil {
                    Button("继续登录") { login() }.buttonStyle(.borderedProminent).disabled(task != nil || model.state.settings.microsoftClientID.isEmpty)
                }
            }
        }.padding(30).frame(width: 500).onDisappear { task?.cancel() }
    }
    private func login() {
        error = nil
        task = Task {
            do {
                let auth = MicrosoftAuth(clientID: model.state.settings.microsoftClientID)
                let code = try await auth.begin(); self.code = code
                NSWorkspace.shared.open(code.verification_uri)
                let (account, credentials) = try await auth.finish(code)
                try Task.checkCancellation(); try model.addMicrosoft(account, credentials: credentials); dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; code = nil } }
            task = nil
        }
    }
}

struct JavaView: View {
    @Environment(AppModel.self) private var model
    @State private var available: [RemoteJava] = []
    @State private var javaError: String?
    @State private var loadingRemote = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeading(title: "为游戏选对 Java", subtitle: "自动识别版本与架构，让每个实例使用合适的运行时。")
                    Spacer(); Button("重新检测", systemImage: "arrow.clockwise") { Task { await model.scanJava() } }.disabled(model.scanningJava)
                }
                if model.scanningJava { ProgressView("正在检测本机 Java…") }
                if model.runtimes.isEmpty && !model.scanningJava { EmptyPanel(symbol: "cup.and.saucer", title: "没有找到 Java", detail: "安装与游戏版本匹配的 Java，然后重新检测。") }
                ForEach(model.runtimes) { java in
                    Surface {
                        HStack(spacing: 18) {
                            Text("\(java.major)").font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent).frame(width: 54, height: 54).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(java.label).font(.headline); if java.isNative { TagPill(text: "原生") } }
                                Text(java.version).font(.caption).foregroundStyle(.secondary)
                                Text(java.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(java.path)
                            }
                            Spacer(); Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: java.path)]) } label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("在 Finder 中显示")
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("下载官方游戏运行时").font(.headline)
                        Text("Minecraft 的 Java 要求以版本清单为准。旧版游戏可能需要 Intel Java 和 Rosetta；较新版本优先使用 Apple Silicon 原生运行时。").font(.callout).foregroundStyle(.secondary)
                        if loadingRemote { ProgressView("获取 Mojang 运行时列表…").controlSize(.small) }
                        if let javaError { Text(javaError).font(.caption).foregroundStyle(.orange) }
                        ForEach(available) { runtime in
                            let installed = model.runtimes.contains { $0.path.hasPrefix(model.paths.runtimes.appendingPathComponent(runtime.id).path + "/") }
                            let resumable = FileManager.default.fileExists(atPath: model.paths.runtimes.appendingPathComponent(".partial-\(runtime.id)").path)
                            HStack {
                                Text(runtime.label).font(.callout)
                                Spacer()
                                Button(installed ? "已安装" : resumable ? "继续安装" : "安装") {
                                    model.perform("安装 Java \(runtime.major)") { id in
                                        _ = try await JavaInstaller(paths: model.paths).install(runtime, downloader: model.installer.downloader) { p in await model.progress(id, p) }
                                        await model.scanJava()
                                    }
                                    model.page = .downloads
                                }.disabled(model.busy || installed)
                            }
                        }
                        HStack { Link("Azul Zulu 下载", destination: URL(string: "https://www.azul.com/downloads/?package=jdk#zulu")!); Link("Eclipse Temurin 下载", destination: URL(string: "https://adoptium.net/temurin/releases/?os=mac")!) }.font(.callout)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(30)
        }.task {
            loadingRemote = true
            do { available = try await JavaInstaller(paths: model.paths).available() } catch { javaError = error.localizedDescription }
            loadingRemote = false
        }
    }
}

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @State private var showLaunchDefaults = false
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: "按你的习惯", subtitle: "为下一次启动做好准备。 ").padding(30)
            Form {
                Section("外观") {
                    Picker("主题", selection: $model.state.settings.appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                }
                Section("游戏默认设置") {
                    LabeledContent("默认最大内存", value: "\(model.state.settings.defaultMemoryMB) MB")
                    Button("编辑默认启动设置…", systemImage: "slider.horizontal.3") { showLaunchDefaults = true }
                    Text("内存、Java、窗口和附加参数可被实例继承；实例也可按项覆盖。").font(.caption).foregroundStyle(.secondary)
                    Picker("新实例隔离规则", selection: Binding(get: { model.state.settings.isolationPolicy ?? .always }, set: { model.state.settings.isolationPolicy = $0 })) {
                        ForEach(GameIsolationPolicy.allCases) { Text($0.title).tag($0) }
                    }
                    Text("仅用于此后新建的实例，已有实例保持原目录。导入的整合包始终独立；共享目录中的实例共用模组、存档和游戏设置，一次只能运行一个。").font(.caption).foregroundStyle(.secondary)
                }
                Section("下载与网络") {
                    Picker("下载源", selection: Binding(get: { model.state.settings.downloadSource ?? .automatic }, set: { model.state.settings.downloadSource = $0 })) {
                        ForEach(DownloadSource.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("并行下载：\(model.state.settings.concurrentDownloads)", value: $model.state.settings.concurrentDownloads, in: 1...16)
                    Text("自动切换会优先使用官方源，连接失败时尝试 BMCLAPI。镜像用于游戏资源和加载器下载，账号登录始终连接原服务。支持范围请求的文件可在取消后继续下载。").font(.caption).foregroundStyle(.secondary)
                    Link("BMCLAPI 镜像服务", destination: URL(string: "https://bmclapidoc.bangbang93.com/")!)
                }
                Section("Microsoft 登录") {
                    TextField("应用 Client ID", text: $model.state.settings.microsoftClientID).font(.system(.body, design: .monospaced))
                    Text("使用 Ruri 自己注册的 Microsoft 公共客户端应用。应用还需要获准访问 Minecraft 服务；这里不使用其他启动器的 Client ID。").font(.caption).foregroundStyle(.secondary)
                    Link("Microsoft 应用注册文档", destination: URL(string: "https://learn.microsoft.com/entra/identity-platform/quickstart-register-app")!)
                }
                CurseForgeSettingsSection()
                Section("数据") {
                    Button("管理实例文件夹…", systemImage: "folder.badge.gearshape") { model.showDirectories = true }
                    LabeledContent("数据目录") { Text(model.paths.root.path).font(.caption).textSelection(.enabled) }
                    Button("在 Finder 中打开数据目录", systemImage: "folder") { do { try model.paths.prepare(); NSWorkspace.shared.open(model.paths.root) } catch { model.error = error.localizedDescription } }
                }
                Section("关于 Ruri") {
                    LabeledContent("版本", value: "0.1.0 · 开发预览")
                    Text("原生 SwiftUI Minecraft Java 启动器。与 Mojang、Microsoft 无隶属关系。参考 HMCL 的功能与兼容策略，使用独立的 Swift 实现。").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }
        .onChange(of: model.state.settings.appearance) { model.save() }
        .sheet(isPresented: $showLaunchDefaults) { DefaultLaunchSettingsView(settings: model.state.settings) }
        .onChange(of: model.state.settings.isolationPolicy) { model.save() }
        .onChange(of: model.state.settings.concurrentDownloads) { model.save() }
        .onChange(of: model.state.settings.downloadSource) { model.save(); Task { await model.applyNetworkSettings() } }
        .onChange(of: model.state.settings.microsoftClientID) { model.save() }
    }
}
