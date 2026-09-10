import SwiftUI
import RuriCore

struct InstanceComponentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var loader: LoaderKind
    @State private var version: String
    @State private var versions: [String] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var backup: ComponentBackup?
    private var reason: String? { InstanceComponents.unavailableReason(instance) }
    private var changed: Bool { loader != instance.loader || (loader != .vanilla && version != instance.loaderVersion) }

    init(instance: GameInstance) {
        self.instance = instance; _loader = State(initialValue: instance.loader)
        _version = State(initialValue: instance.loaderVersion ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "管理加载器", subtitle: instance.name + " · Minecraft " + instance.gameVersion)
            LabeledContent("当前", value: instance.loader.title + (instance.loaderVersion.map { " " + $0 } ?? ""))
            if let reason { Label(reason, systemImage: "info.circle").foregroundStyle(.secondary) }
            else {
                Picker("加载器", selection: $loader) {
                    ForEach(LoaderKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                if loader != .vanilla {
                    if loader == .optifine { Text("OptiFine 版本与安装包由 BMCLAPI 提供。").font(.caption).foregroundStyle(.secondary) }
                    if loading { ProgressView("正在查找兼容版本…").controlSize(.small) }
                    else if let error {
                        Text(error).font(.callout).foregroundStyle(.orange)
                        Button("重试") { retry += 1 }
                    } else {
                        Picker("版本", selection: $version) {
                            ForEach(versions, id: \.self) { value in
                                Text(value + (loader == instance.loader && value == instance.loaderVersion ? "（当前）" : "")).tag(value)
                            }
                        }
                    }
                }
                Text(loader == .vanilla ? "移除加载器后按原版启动，模组文件仍会保留。" : "可升级、降级或更换加载器。现有模组需要与所选加载器兼容。")
                    .font(.callout).foregroundStyle(.secondary)
                Text("保留存档、模组、游戏客户端和实例设置；重新生成启动清单，其中的自定义修改不会继承。应用成功后可恢复上次的加载器配置。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let backup {
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text("上次配置：" + backup.title).font(.callout)
                        Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("恢复上次配置") { model.restoreComponents(instance); dismiss() }
                        .disabled(model.busy || model.isInstanceInUse(instance.id))
                }
            }
            HStack {
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
                if reason == nil {
                    Button(loader == .vanilla ? "移除加载器" : "应用加载器") {
                        model.changeComponents(instance, loader: loader, version: loader == .vanilla ? nil : version); dismiss()
                    }.buttonStyle(.borderedProminent)
                        .disabled(!changed || model.busy || model.isInstanceInUse(instance.id) || (loader != .vanilla && (loading || error != nil || version.isEmpty)))
                }
            }
        }.padding(24).frame(width: 560)
        .task {
            do { backup = try await InstanceComponents(paths: model.paths).backup(for: instance.id) }
            catch { model.notice = error.localizedDescription }
        }
        .task(id: loader.rawValue + String(retry)) {
            guard reason == nil else { return }
            versions = []; version = ""; error = nil; loading = loader != .vanilla
            guard loader != .vanilla else { return }
            do {
                var result = try await model.installer.loaderVersions(loader, game: instance.gameVersion)
                try Task.checkCancellation()
                if loader == instance.loader, let current = instance.loaderVersion {
                    if !result.contains(current) { result.insert(current, at: 0) }
                    version = current
                } else { version = result.first ?? "" }
                versions = result
                if result.isEmpty { error = "此 Minecraft 版本没有兼容的加载器版本。" }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}
