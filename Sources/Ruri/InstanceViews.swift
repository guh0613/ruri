import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct CreateInstanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedVersion = ""
    @State private var loader = LoaderKind.vanilla
    @State private var loaderVersion = ""
    @State private var loaders: [String] = []
    @State private var search = ""
    @State private var snapshots = false
    @State private var loadingLoader = false
    @State private var loaderError: String?
    var versions: [VersionEntry] { (model.catalog?.versions ?? []).filter { (snapshots || $0.isRelease) && (search.isEmpty || $0.id.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { SectionHeading(title: "创建一个新世界", subtitle: "选择版本，剩下的交给 Ruri。 "); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            TextField("实例名称（可选）", text: $name).textFieldStyle(.roundedBorder)
            Label("保存到：\(model.selectedDirectoryName)", systemImage: "folder").font(.callout).foregroundStyle(.secondary)
            HStack { TextField("搜索 Minecraft 版本", text: $search).textFieldStyle(.roundedBorder); Toggle("快照与旧版", isOn: $snapshots).toggleStyle(.checkbox) }
            if model.catalogLoading && model.catalog == nil { ProgressView("正在获取版本…").frame(maxWidth: .infinity, minHeight: 220) }
            else if let error = model.catalogError, model.catalog == nil {
                VStack { Text(error).foregroundStyle(.secondary); Button("重试") { Task { await model.refreshCatalog() } } }.frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List(versions, selection: $selectedVersion) { version in
                    HStack {
                        Text(version.id).font(.system(.body, design: .monospaced).weight(.medium))
                        if version.id == model.catalog?.latest.release { TagPill(text: "最新正式版") }
                        Spacer()
                        Text(String(version.releaseTime.prefix(10))).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(version.id)
                }.listStyle(.bordered).frame(height: 230)
            }
            HStack {
                Picker("加载器", selection: $loader) { ForEach(LoaderKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            }
            if loader != .vanilla {
                if loadingLoader { ProgressView("查找兼容的加载器…").controlSize(.small) }
                else if let loaderError { Text(loaderError).font(.caption).foregroundStyle(.red) }
                else { Picker("加载器版本", selection: $loaderVersion) { ForEach(loaders, id: \.self) { Text($0).tag($0) } } }
            }
            HStack {
                Text((model.state.settings.isolationPolicy ?? .always).directory(loader: loader).title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("创建并安装") { model.install(name: name, version: selectedVersion, loader: loader, loaderVersion: loader == .vanilla ? nil : loaderVersion) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selectedVersion.isEmpty || model.busy || (loader != .vanilla && (loaderVersion.isEmpty || loadingLoader)))
            }
        }.padding(28).frame(width: 570)
        .task { if model.catalog == nil { await model.refreshCatalog() }; if selectedVersion.isEmpty { selectedVersion = model.catalog?.latest.release ?? "" } }
        .task(id: selectedVersion + loader.rawValue) {
            loaders = []; loaderVersion = ""; loaderError = nil
            guard loader != .vanilla, !selectedVersion.isEmpty else { return }
            loadingLoader = true
            do {
                let result = try await model.installer.loaderVersions(loader, game: selectedVersion)
                try Task.checkCancellation(); loaders = result; loaderVersion = result.first ?? ""
                if result.isEmpty { loaderError = "此 Minecraft 版本暂无兼容加载器。" }
            } catch { if !Task.isCancelled { loaderError = error.localizedDescription } }
            loadingLoader = false
        }
    }
}

struct InstanceSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var instance: GameInstance
    @State private var changingDirectory = false
    @State private var relocatingDirectory = false
    @State private var launchOverrides: InstanceLaunchOverrides
    @State private var settingsIssue: String?
    @State private var preservedWorkspaces: [URL] = []
    private let original: GameInstance
    private var locationInstance: GameInstance { model.state.instances.first(where: { $0.id == instance.id }) ?? instance }
    private var directoryCopyPending: Bool { model.pendingDirectoryCopyIDs.contains(instance.id) || RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) }
    init(instance: GameInstance) { _instance = State(initialValue: instance); _launchOverrides = State(initialValue: instance.effectiveLaunchOverrides); original = instance }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { InstanceIcon(loader: instance.loader); SectionHeading(title: "实例设置", subtitle: instance.subtitle) }
            Form {
                Section("基本信息") { TextField("名称", text: $instance.name); Toggle("收藏此实例", isOn: $instance.favorite) }
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
                    if !preservedWorkspaces.isEmpty {
                        Menu("查看保留的复制副本") {
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
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(instance.name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 620, height: 590)
        .sheet(isPresented: $changingDirectory) { GameRunDirectoryChangeView(instance: locationInstance) }
        .sheet(isPresented: $relocatingDirectory) { CustomRunDirectoryRelocationView(instanceID: instance.id) }
        .task(id: model.busy) {
            guard !model.busy else { return }
            let paths = model.paths, id = instance.id
            let locations = await Task.detached(priority: .utility) { RunDirectoryCopyGuard.preservedWorkspaces(paths: paths, instanceID: id) }.value
            if !Task.isCancelled { preservedWorkspaces = locations }
        }
    }
}

struct DownloadsView: View {
    @Environment(AppModel.self) private var model
    @State private var transfers: [FileTransfer] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "下载任务", subtitle: "文件自动校验，重试时继续下载可用的未完成文件。")
                if model.activities.isEmpty { EmptyPanel(symbol: "arrow.down.circle", title: "一切就绪", detail: "安装游戏或下载内容时，可以在这里查看进度。") }
                ForEach(model.activities) { activity in
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: activity.status == .completed ? "checkmark.circle.fill" : activity.status == .failed ? "exclamationmark.circle" : "arrow.down.circle").foregroundStyle(activity.status == .failed ? Color.orange : Theme.accent)
                                Text(activity.title).font(.headline); Spacer()
                                if activity.status == .running { Button("取消") { model.operation?.cancel() } }
                                else { Text(activity.status == .completed ? "已完成" : activity.status == .cancelled ? "已取消" : "失败").font(.caption).foregroundStyle(.secondary) }
                            }
                            if activity.status == .running {
                                if activity.progress.total > 0 { ProgressView(value: activity.progress.fraction) }
                                else { ProgressView().controlSize(.small) }
                                HStack { Text(activity.progress.stage); Spacer(); if activity.progress.total > 0 { Text("\(activity.progress.completed) / \(activity.progress.total)").monospacedDigit() } }.font(.caption).foregroundStyle(.secondary)
                            }
                            if let error = activity.error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                        }
                    }
                }
                if !transfers.isEmpty {
                    Text("最近的文件传输").font(.headline)
                    Surface {
                        VStack(spacing: 15) {
                            ForEach(transfers) { transfer in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(transfer.filename).font(.callout.weight(.medium)).lineLimit(1)
                                        Spacer()
                                        Text(transfer.state.title).font(.caption).foregroundStyle(transfer.state == .failed ? .orange : .secondary)
                                    }
                                    if transfer.state.isActive, let total = transfer.totalBytes, total > 0 { ProgressView(value: min(Double(transfer.receivedBytes) / Double(total), 1)) }
                                    ViewThatFits(in: .horizontal) {
                                        HStack { sourceInfo(transfer).fixedSize(); Spacer(minLength: 12); byteInfo(transfer).fixedSize() }
                                        VStack(alignment: .leading, spacing: 4) { sourceInfo(transfer); byteInfo(transfer) }
                                    }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    if let message = transfer.message, transfer.state != .cancelled { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                }
                                if transfer.id != transfers.last?.id { Divider() }
                            }
                        }
                    }
                }
            }.padding(30)
        }
        .task {
            while !Task.isCancelled {
                transfers = await model.installer.downloader.transfers()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func sourceInfo(_ transfer: FileTransfer) -> some View {
        HStack {
            Text(transfer.host).lineLimit(1).truncationMode(.middle)
            if transfer.attempt > 1 { Text("第 \(transfer.attempt) 次尝试") }
            if transfer.resumedBytes > 0 { Text("续传 \(bytes(transfer.resumedBytes))") }
        }
    }
    private func byteInfo(_ transfer: FileTransfer) -> some View {
        HStack {
            Text(bytes(transfer.receivedBytes) + (transfer.totalBytes.map { " / " + bytes($0) } ?? ""))
            if transfer.state == .receiving, transfer.bytesPerSecond > 0 { Text(bytes(Int64(transfer.bytesPerSecond)) + "/s") }
        }
    }
}
