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
                Text("游戏资源共享，存档与模组独立。").font(.caption).foregroundStyle(.secondary)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { InstanceIcon(loader: instance.loader); SectionHeading(title: "实例设置", subtitle: instance.subtitle) }
            Form {
                Section("基本信息") { TextField("名称", text: $instance.name); Toggle("收藏此实例", isOn: $instance.favorite) }
                Section("Java 与内存") {
                    Picker("Java 运行时", selection: Binding(get: { instance.javaPath ?? "" }, set: { instance.javaPath = $0.isEmpty ? nil : $0 })) {
                        Text("自动选择兼容版本").tag("")
                        ForEach(model.runtimes) { Text($0.label).tag($0.path) }
                    }
                    if let versions = instance.supportedJavaMajors, !versions.isEmpty { Text("整合包支持 Java：" + versions.map(String.init).joined(separator: "、")).font(.caption).foregroundStyle(.secondary) }
                    LabeledContent("最大内存", value: "\(instance.memoryMB) MB")
                    Slider(value: Binding(get: { Double(instance.memoryMB) }, set: { instance.memoryMB = Int($0) }), in: 1024...Double(max(2048, min(32768, ProcessInfo.processInfo.physicalMemory / 1024 / 1024))), step: 512)
                    TextField("附加 JVM 参数", text: $instance.extraJVMArguments).font(.system(.body, design: .monospaced))
                }
                Section("游戏窗口") {
                    TextField("附加游戏参数", text: Binding(get: { instance.extraGameArguments ?? "" }, set: { instance.extraGameArguments = $0.isEmpty ? nil : $0 })).font(.system(.body, design: .monospaced))
                    TextField("宽度", value: $instance.width, format: .number)
                    TextField("高度", value: $instance.height, format: .number)
                }
                Section("实例文件") {
                    HStack {
                        Button("打开文件夹", systemImage: "folder") { model.reveal(instance) }
                        Button("模组", systemImage: "puzzlepiece.extension") { model.reveal(instance, folder: "mods") }
                        Button("存档", systemImage: "globe") { model.reveal(instance, folder: "saves") }
                    }
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { model.update(instance); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(instance.name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(24).frame(width: 620, height: 630)
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
