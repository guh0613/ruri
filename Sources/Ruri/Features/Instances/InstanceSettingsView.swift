import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct InstanceSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var instance: GameInstance
    @State private var pane = InstanceSettingsPane.overview
    @State private var changingDirectory = false
    @State private var relocatingDirectory = false
    @State private var copyingInstance = false
    @State private var movingInstance = false
    @State private var managingComponents = false
    @State private var updatingModpack = false
    @State private var launchOverrides: InstanceLaunchOverrides
    @State private var settingsIssue: String?
    @State private var loadingIcon = false
    @State private var preservedWorkspaces: [URL] = []
    private let original: GameInstance
    private var locationInstance: GameInstance { model.state.instances.first(where: { $0.id == instance.id }) ?? instance }
    private var directoryCopyPending: Bool { model.pendingDirectoryCopyIDs.contains(instance.id) || RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) }
    init(instance: GameInstance) { _instance = State(initialValue: instance); _launchOverrides = State(initialValue: instance.effectiveLaunchOverrides); original = instance }
    private var hasChanges: Bool {
        instance.name != original.name || instance.favorite != original.favorite || instance.iconPNG != original.iconPNG || launchOverrides != original.effectiveLaunchOverrides
    }
    var body: some View {
        VStack(spacing: 0) {
            SettingsLayout(title: "实例设置", subtitle: instance.name, selection: $pane) {
                switch pane {
                case .overview: overview
                case .files: files
                default:
                    if pane == .runtime, let versions = instance.supportedJavaMajors, !versions.isEmpty {
                        Section { LabeledContent("整合包支持的 Java", value: versions.map(String.init).joined(separator: "、")) }
                    }
                    LaunchSettingsEditor(overrides: $launchOverrides, defaults: model.state.settings.defaultLaunchSettings, runtimes: model.runtimes, keys: pane.launchKeys)
                }
            }
            Divider()
            if let settingsIssue {
                Label(settingsIssue, systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 12)
            }
            HStack(spacing: 12) {
                Menu("恢复默认") { Button("恢复所有启动设置") { launchOverrides = .init(); settingsIssue = nil } }
                    .fixedSize().help("恢复启动设置的继承关系，保留名称和图标。")
                Text(hasChanges ? "有未保存的更改" : "设置用于下一次启动").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || loadingIcon || model.readOnly)
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 860, height: 670)
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: launchOverrides) { _, _ in settingsIssue = nil }
        .onChange(of: instance.name) { _, _ in settingsIssue = nil }
        .sheet(isPresented: $changingDirectory) { GameRunDirectoryChangeView(instance: locationInstance) }
        .sheet(isPresented: $relocatingDirectory) { CustomRunDirectoryRelocationView(instanceID: instance.id) }
        .sheet(isPresented: $copyingInstance) { InstanceCopyView(instance: locationInstance) }
        .sheet(isPresented: $movingInstance) { InstanceMoveView(instance: locationInstance) }
        .sheet(isPresented: $managingComponents) { InstanceComponentsView(instance: locationInstance) }
        .sheet(isPresented: $updatingModpack) { ModpackUpdateView(instance: locationInstance) }
        .task(id: model.busy) {
            guard !model.busy else { return }
            let paths = model.paths, id = instance.id
            let locations = await Task.detached(priority: .utility) {
                RunDirectoryCopyGuard.preservedWorkspaces(paths: paths, instanceID: id) + InstanceCopyGuard.preservedWorkspaces(paths: paths, sourceID: id) + InstanceMoveGuard.preservedWorkspaces(paths: paths, instanceID: id)
            }.value
            if !Task.isCancelled { preservedWorkspaces = locations }
        }
    }
    @ViewBuilder private var overview: some View {
        Section("实例信息") {
            LabeledContent("名称") {
                TextField("实例名称", text: $instance.name, prompt: Text("输入实例名称"))
                    .labelsHidden().textFieldStyle(.roundedBorder).frame(minWidth: 220).accessibilityLabel("实例名称")
            }
            Toggle("收藏此实例", isOn: $instance.favorite)
            HStack(spacing: 14) {
                InstanceIcon(loader: locationInstance.loader, size: 48, png: instance.iconPNG)
                VStack(alignment: .leading, spacing: 4) {
                    Text("实例图标")
                    Text("选择图片后会自动裁剪为正方形。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if loadingIcon { ProgressView().controlSize(.small) }
                Menu("更改图标") {
                    Button("选择图片…", action: chooseIcon)
                    if instance.iconPNG != nil { Button("恢复默认图标") { instance.iconPNG = nil } }
                }.fixedSize().disabled(loadingIcon)
            }.padding(.vertical, 5)
        }
        Section("游戏组件") {
            LabeledContent("Minecraft", value: locationInstance.gameVersion)
            SettingsActionRow(title: "加载器", detail: locationInstance.subtitle, button: "管理…") { managingComponents = true }
                .disabled(model.busy || model.isInstanceInUse(instance.id) || !locationInstance.installed)
            SettingsActionRow(title: "整合包更新", detail: "检查版本、安装更新或恢复上次配置。", button: "查看…") { updatingModpack = true }
                .disabled(model.busy || (!ModpackUpdateStore.hasPending(paths: model.paths, instanceID: instance.id) && model.isInstanceInUse(instance.id)))
        }
    }
    @ViewBuilder private var files: some View {
        Section("运行目录") {
            LabeledContent("保存方式", value: (locationInstance.runDirectory ?? .isolated).title)
            VStack(alignment: .leading, spacing: 6) {
                Text((locationInstance.runDirectory ?? .isolated).explanation).font(.caption).foregroundStyle(.secondary)
                Text(model.paths.game(instance.id).path).font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.customDirectoryErrors[instance.id] { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            LabeledContent("位置与隔离") {
                Button(directoryCopyPending ? "恢复目录复制…" : "切换运行目录…") { changingDirectory = true }
                    .disabled(model.busy || (!directoryCopyPending && model.isInstanceInUse(instance.id)))
            }
            if locationInstance.customRunDirectory != nil {
                Button(locationInstance.runDirectory == .custom ? "重新定位原游戏目录…" : "重新定位记住的自定义目录…") { relocatingDirectory = true }.disabled(model.busy)
            }
            HStack {
                Button("打开文件夹", systemImage: "folder") { model.reveal(locationInstance) }
                Spacer()
                Button("模组") { model.reveal(locationInstance, folder: "mods") }
                Button("存档") { model.reveal(locationInstance, folder: "saves") }
            }
        }
        Section {
            if model.pendingInstanceCopyIDs.contains(instance.id) || InstanceCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                SettingsActionRow(title: "未完成的实例复制", detail: "继续处理上次复制保留的文件。", button: "恢复…") { copyingInstance = true }.disabled(model.busy)
            } else {
                SettingsActionRow(title: "复制实例", detail: "保留原实例，创建一份独立副本。", button: "复制…") { copyingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
            }
            if model.pendingInstanceMoveIDs.contains(instance.id) || InstanceMoveGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                SettingsActionRow(title: "未完成的实例移动", detail: "继续处理上次移动保留的文件。", button: "恢复…") { movingInstance = true }.disabled(model.busy)
            } else {
                SettingsActionRow(title: "移动实例", detail: "将实例转移到其他游戏文件夹。", button: "移动…") { movingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
            }
        } header: { Text("复制与移动") } footer: { Text("文件操作会在对应页面确认后执行，无需点击这里的“保存”。") }
        if !preservedWorkspaces.isEmpty {
            Section("保留的工作文件") {
                ForEach(Array(preservedWorkspaces.enumerated()), id: \.offset) { index, url in
                    LabeledContent("副本 \(index + 1)") { Button("在 Finder 中查看") { NSWorkspace.shared.open(url) } }
                }
            }
        }
    }
    private func save() {
        guard !instance.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { pane = .overview; settingsIssue = "请填写实例名称。"; return }
        let effective = launchOverrides.resolve(defaults: model.state.settings.defaultLaunchSettings)
        if let issue = SettingsValidation.issue(in: effective) { pane = .containing(issue.key); settingsIssue = issue.message; return }
        instance.launchOverrides = launchOverrides
        if model.updateSettings(instance, basedOn: original) { dismiss() }
        else { settingsIssue = model.error ?? "此实例已不在当前文件夹中，请关闭设置后刷新。" }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = "选择图标"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadingIcon = true
        Task {
            defer { loadingIcon = false }
            do { instance.iconPNG = try await Task.detached(priority: .userInitiated) { try InstanceIconImage.load(url) }.value }
            catch { settingsIssue = error.localizedDescription }
        }
    }
}
