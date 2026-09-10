import SwiftUI
import AppKit
import RuriCore

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
                    LabeledContent("默认内存分配", value: model.state.settings.defaultLaunchSettings.memory.mode == .automatic ? "自动估算" : "\(model.state.settings.defaultMemoryMB) MB")
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
                    Link("BMCLAPI 镜像服务", destination: AppLinks.bmclapiDocumentation)
                }
                Section("Microsoft 登录") {
                    TextField("应用 Client ID", text: $model.state.settings.microsoftClientID).font(.system(.body, design: .monospaced))
                    Text("使用 Ruri 自己注册的 Microsoft 公共客户端应用。应用还需要获准访问 Minecraft 服务；这里不使用其他启动器的 Client ID。").font(.caption).foregroundStyle(.secondary)
                    Link("Microsoft 应用注册文档", destination: AppLinks.microsoftRegistration)
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
