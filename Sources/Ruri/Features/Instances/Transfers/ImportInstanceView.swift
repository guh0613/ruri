import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ImportInstanceView: View {
    @Environment(AppModel.self) private var model
    let prepared: PreparedInstanceImport
    @State private var name: String
    @State private var keepJVMArguments = false
    @State private var files: [PlannedCurseFile]?
    @State private var excluded = Set<Int>()
    @State private var excludedOptional = Set<String>()
    private var selectedImport: PreparedInstanceImport { prepared.selectingOptionalFiles(excluding: excludedOptional) }
    @State private var manualFiles: [Int: URL] = [:]
    @State private var resolving = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    private var chosenFiles: [PlannedCurseFile] { files?.filter { !excluded.contains($0.id) } ?? [] }
    private var ready: Bool { prepared.curseForgeFiles.isEmpty || files != nil && chosenFiles.filter(\.requiresManualDownload).allSatisfy { manualFiles[$0.id] != nil } }
    init(prepared: PreparedInstanceImport) { self.prepared = prepared; _name = State(initialValue: prepared.instance.name); _keepJVMArguments = State(initialValue: prepared.format == "MCBBS"); _excludedOptional = State(initialValue: prepared.omittedOptionalPaths) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("导入游戏实例", systemImage: "square.and.arrow.down").font(.title2.bold())
            Label("保存到：\(model.selectedDirectoryName)", systemImage: "folder").font(.callout).foregroundStyle(.secondary)
            Text("整合包会使用独立运行目录，存档和模组保存在新版本文件夹中。").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("已识别 \(prepared.format) 实例。游戏依赖将按这台 Mac 的系统与架构安装。").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("实例名称") { TextField("实例名称", text: $name).textFieldStyle(.roundedBorder) }
                        LabeledContent("游戏版本", value: prepared.instance.subtitle)
                        LabeledContent("内存", value: "\(prepared.instance.memoryMB) MB")
                        LabeledContent("窗口", value: "\(prepared.instance.width) × \(prepared.instance.height)")
                        if let java = prepared.instance.supportedJavaMajors, !java.isEmpty { LabeledContent("支持 Java", value: java.map(String.init).joined(separator: "、")) }
                        if selectedImport.remoteFileCount > 0 { LabeledContent("待下载文件", value: "\(selectedImport.remoteFileCount) 个（整合包下载源）") }
                        LabeledContent("迁移内容", value: "\(prepared.fileCount) 个文件 · \(ByteCountFormatter.string(fromByteCount: prepared.byteCount, countStyle: .file))")
                    }.padding(16).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    if !prepared.optionalFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("可选内容").font(.headline)
                            ForEach(prepared.optionalFiles) { file in
                                Toggle(file.path, isOn: Binding(get: { !excludedOptional.contains(file.path) }, set: { if $0 { excludedOptional.remove(file.path) } else { excludedOptional.insert(file.path) } })).font(.callout)
                            }
                        }
                    }
                    if !prepared.curseForgeFiles.isEmpty {
                        if let files {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(files) { item in
                                        let optional = prepared.curseForgeFiles.first { $0.fileID == item.id }?.required == false
                                        if optional {
                                            Toggle("安装可选内容：\(item.project.name)", isOn: Binding(get: { !excluded.contains(item.id) }, set: { if $0 { excluded.remove(item.id) } else { excluded.insert(item.id) } }))
                                        }
                                        if !excluded.contains(item.id) {
                                            CurseForgeFileRow(file: item.file, title: item.project.name, page: item.pageURL, manual: item.requiresManualDownload, selectedURL: Binding(get: { manualFiles[item.id] }, set: { manualFiles[item.id] = $0 }))
                                        }
                                    }
                                }
                            }.frame(maxHeight: 230)
                        } else if resolving { ProgressView("正在解析整合包文件…") }
                        else {
                            Text("继续前需要解析 CurseForge 文件清单。").foregroundStyle(.secondary)
                            if model.curseForgeConfigured { Button("解析文件清单") { resolve() } }
                            else { Text("可在设置中配置 API Key，再重新导入此整合包。").font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.orange) }
                    if !prepared.warnings.isEmpty && files == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(prepared.warnings, id: \.self) { warning in Label(warning, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                    if let arguments = prepared.instance.extraGameArguments, !arguments.isEmpty { Text("游戏参数：" + arguments).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    if !prepared.instance.extraJVMArguments.isEmpty {
                        Toggle("保留自定义 JVM 参数", isOn: $keepJVMArguments)
                        ScrollView { Text(prepared.instance.extraJVMArguments).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 75)
                    }
                }
            }
            HStack {
                Button("取消") { task?.cancel(); model.cancelImport(prepared) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("导入实例") { model.finishImport(selectedImport, name: name, keepJVMArguments: keepJVMArguments, curseFiles: chosenFiles, manualFiles: manualFiles) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || resolving || !ready || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(26).frame(width: 560, height: 600).interactiveDismissDisabled()
        .onAppear { if model.curseForgeConfigured && !prepared.curseForgeFiles.isEmpty { resolve() } }
        .onDisappear { task?.cancel() }
    }
    private func resolve() {
        resolving = true; error = nil
        task = Task {
            do {
                let result = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).resolve(prepared.curseForgeFiles)
                try Task.checkCancellation(); files = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            resolving = false
        }
    }
}
