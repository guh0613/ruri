import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ImportInstanceView: View {
    @Environment(AppModel.self) private var model
    let prepared: PreparedInstanceImport
    @State private var name: String
    @State private var keepJVMArguments = false
    init(prepared: PreparedInstanceImport) { self.prepared = prepared; _name = State(initialValue: prepared.instance.name) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("导入游戏实例", systemImage: "square.and.arrow.down").font(.title2.bold())
            Text("已识别 \(prepared.format) 实例。游戏依赖将按这台 Mac 的系统与架构安装。").foregroundStyle(.secondary)
            Form {
                TextField("实例名称", text: $name)
                LabeledContent("游戏版本", value: prepared.instance.subtitle)
                LabeledContent("内存", value: "\(prepared.instance.memoryMB) MB")
                LabeledContent("窗口", value: "\(prepared.instance.width) × \(prepared.instance.height)")
                LabeledContent("迁移内容", value: "\(prepared.fileCount) 个文件 · \(ByteCountFormatter.string(fromByteCount: prepared.byteCount, countStyle: .file))")
            }.formStyle(.grouped)
            if !prepared.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(prepared.warnings, id: \.self) { warning in Label(warning, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                }
            }
            if !prepared.instance.extraJVMArguments.isEmpty {
                Toggle("保留自定义 JVM 参数", isOn: $keepJVMArguments)
                ScrollView { Text(prepared.instance.extraJVMArguments).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 75)
            }
            HStack {
                Button("取消") { model.cancelImport(prepared) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("导入实例") { model.finishImport(prepared, name: name, keepJVMArguments: keepJVMArguments) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 560).interactiveDismissDisabled()
    }
}

struct ExportInstanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var format = InstanceExportFormat.ruri
    @State private var includeWorlds = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("导出 \(instance.name)", systemImage: "square.and.arrow.up").font(.title2.bold())
            Text("将模组、配置与游戏设置保存为可迁移的 ZIP。导入时会重新下载游戏依赖。").foregroundStyle(.secondary)
            Picker("导出格式", selection: $format) { ForEach(InstanceExportFormat.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Toggle("包含存档", isOn: $includeWorlds)
            Text(format == .ruri ? "Ruri 格式还会保留模组来源与版本记录，方便继续检查更新。" : "可通过 Prism 或 MultiMC 的实例导入功能打开。跨平台迁移后，部分模组可能需要重新配置。").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("选择保存位置…") { chooseDestination() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || model.runningID == instance.id)
            }
        }.padding(26).frame(width: 510)
    }
    private func chooseDestination() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = instance.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(instance, to: url, format: format, includeWorlds: includeWorlds); dismiss()
    }
}

extension AppModel {
    func chooseInstanceImport() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.zip, UTType(filenameExtension: "mrpack") ?? .data]
        panel.message = "选择 Ruri、Prism/MultiMC 实例目录或 ZIP，也可导入 Modrinth 整合包。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPack(url)
    }
    func prepareInstanceImport(_ url: URL) {
        guard !busy else { return }
        perform("读取 \(url.lastPathComponent)") { [self] id in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importingInstance = try await InstanceTransfer(paths: paths).prepare(url) { [weak self] value in Task { @MainActor in self?.progress(id, value) } }
        }
    }
    func cancelImport(_ prepared: PreparedInstanceImport) {
        importingInstance = nil
        Task { await InstanceTransfer(paths: paths).discard(prepared) }
    }
    func finishImport(_ prepared: PreparedInstanceImport, name: String, keepJVMArguments: Bool) {
        guard !busy else { return }
        importingInstance = nil; page = .downloads
        perform("导入 \(name)") { [self] id in
            let service = InstanceTransfer(paths: paths)
            do {
                let instance = try await service.install(prepared, name: name, importJVMArguments: keepJVMArguments, installer: installer, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
                state.instances.append(instance); select(instance); notice = "\(instance.name) 已导入"
                await service.discard(prepared)
            } catch { await service.discard(prepared); throw error }
        }
    }
    func export(_ instance: GameInstance, to url: URL, format: InstanceExportFormat, includeWorlds: Bool) {
        guard runningID != instance.id else { return }
        perform("导出 \(instance.name)") { [self] id in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try await InstanceTransfer(paths: paths).export(instance, to: url, format: format, includeWorlds: includeWorlds) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
            notice = "\(instance.name) 已导出"; NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
