import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct InstanceSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var instance: GameInstance
    @State private var changingDirectory = false
    @State private var relocatingDirectory = false
    @State private var copyingInstance = false
    @State private var movingInstance = false
    @State private var managingComponents = false
    @State private var launchOverrides: InstanceLaunchOverrides
    @State private var settingsIssue: String?
    @State private var loadingIcon = false
    @State private var preservedWorkspaces: [URL] = []
    private let original: GameInstance
    private var locationInstance: GameInstance { model.state.instances.first(where: { $0.id == instance.id }) ?? instance }
    private var directoryCopyPending: Bool { model.pendingDirectoryCopyIDs.contains(instance.id) || RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) }
    init(instance: GameInstance) { _instance = State(initialValue: instance); _launchOverrides = State(initialValue: instance.effectiveLaunchOverrides); original = instance }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { InstanceIcon(loader: locationInstance.loader, png: instance.iconPNG); SectionHeading(title: "实例设置", subtitle: locationInstance.subtitle) }
            Form {
                Section("基本信息") {
                    TextField("名称", text: $instance.name); Toggle("收藏此实例", isOn: $instance.favorite)
                    LabeledContent("图标") {
                        HStack {
                            if loadingIcon { ProgressView().controlSize(.small) }
                            Button("选择图片…", action: chooseIcon).disabled(loadingIcon)
                            if instance.iconPNG != nil { Button("恢复默认") { instance.iconPNG = nil }.disabled(loadingIcon) }
                        }
                    }
                    Text("图片会居中显示为图标，保存后无需保留原图片文件。").font(.caption).foregroundStyle(.secondary)
                }
                Section("游戏组件") {
                    Text(locationInstance.subtitle).font(.callout)
                    Button("管理加载器…", systemImage: "puzzlepiece.extension") { managingComponents = true }
                        .disabled(model.busy || model.isInstanceInUse(instance.id) || !locationInstance.installed)
                }
                Section("启动设置") {
                    Text("各项可跟随默认设置，或由此实例单独覆盖。修改只影响下一次启动。").font(.callout).foregroundStyle(.secondary)
                    Button("所有启动设置恢复默认") { launchOverrides = .init() }
                    if let versions = instance.supportedJavaMajors, !versions.isEmpty { Text("整合包支持 Java：" + versions.map(String.init).joined(separator: "、")).font(.caption).foregroundStyle(.secondary) }
                }
                LaunchSettingsEditor(overrides: $launchOverrides, defaults: model.state.settings.defaultLaunchSettings, runtimes: model.runtimes)
                Section("实例文件") {
                    LabeledContent("运行目录", value: (locationInstance.runDirectory ?? .isolated).title)
                    Text((locationInstance.runDirectory ?? .isolated).explanation).font(.caption).foregroundStyle(.secondary)
                    Text(model.paths.game(instance.id).path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if let error = model.customDirectoryErrors[instance.id] { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    Button(directoryCopyPending ? "恢复目录复制…" : "切换运行目录…", systemImage: "arrow.triangle.swap") { changingDirectory = true }.disabled(model.busy || (!directoryCopyPending && model.isInstanceInUse(instance.id)))
                    if locationInstance.customRunDirectory != nil {
                        Button(locationInstance.runDirectory == .custom ? "重新定位原游戏目录…" : "重新定位记住的自定义目录…", systemImage: "folder.badge.questionmark") { relocatingDirectory = true }.disabled(model.busy)
                    }
                    if model.pendingInstanceCopyIDs.contains(instance.id) || InstanceCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                        Button("恢复实例复制…", systemImage: "arrow.counterclockwise") { copyingInstance = true }.disabled(model.busy)
                    } else {
                        Button("复制实例…", systemImage: "plus.square.on.square") { copyingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
                    }
                    if model.pendingInstanceMoveIDs.contains(instance.id) || InstanceMoveGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                        Button("恢复实例移动…", systemImage: "arrow.counterclockwise") { movingInstance = true }.disabled(model.busy)
                    } else {
                        Button("移动到其他文件夹…", systemImage: "folder.badge.arrow.forward") { movingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
                    }
                    if !preservedWorkspaces.isEmpty {
                        Menu("查看保留的工作文件") {
                            ForEach(Array(preservedWorkspaces.enumerated()), id: \.offset) { index, url in
                                Button("副本 \(index + 1) · " + (url.deletingLastPathComponent().lastPathComponent == ".directory-change-workspaces" ? url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent : "此实例")) { NSWorkspace.shared.open(url) }
                            }
                        }.disabled(model.busy)
                    }
                    HStack {
                        Button("打开文件夹", systemImage: "folder") { model.reveal(instance) }
                        Button("模组", systemImage: "puzzlepiece.extension") { model.reveal(instance, folder: "mods") }
                        Button("存档", systemImage: "globe") { model.reveal(instance, folder: "saves") }
                    }
                }
            }.formStyle(.grouped)
            if let settingsIssue { Text(settingsIssue).foregroundStyle(.red).font(.callout) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") {
                do {
                    try launchOverrides.resolve(defaults: model.state.settings.defaultLaunchSettings).validate()
                    instance.launchOverrides = launchOverrides; model.updateSettings(instance, basedOn: original); dismiss()
                } catch { settingsIssue = error.localizedDescription }
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(loadingIcon || instance.name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 620, height: 590)
        .sheet(isPresented: $changingDirectory) { GameRunDirectoryChangeView(instance: locationInstance) }
        .sheet(isPresented: $relocatingDirectory) { CustomRunDirectoryRelocationView(instanceID: instance.id) }
        .sheet(isPresented: $copyingInstance) { InstanceCopyView(instance: locationInstance) }
        .sheet(isPresented: $movingInstance) { InstanceMoveView(instance: locationInstance) }
        .sheet(isPresented: $managingComponents) { InstanceComponentsView(instance: locationInstance) }
        .task(id: model.busy) {
            guard !model.busy else { return }
            let paths = model.paths, id = instance.id
            let locations = await Task.detached(priority: .utility) {
                RunDirectoryCopyGuard.preservedWorkspaces(paths: paths, instanceID: id) + InstanceCopyGuard.preservedWorkspaces(paths: paths, sourceID: id) + InstanceMoveGuard.preservedWorkspaces(paths: paths, instanceID: id)
            }.value
            if !Task.isCancelled { preservedWorkspaces = locations }
        }
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
