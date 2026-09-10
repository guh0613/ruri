import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct SchematicManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var directory = ""
    @State private var entries: [SchematicEntry] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false
    @State private var importing = false
    @State private var creatingFolder = false
    @State private var folderName = ""
    @State private var removing: SchematicEntry?
    @State private var inspecting: SchematicEntry?
    private var manager: SchematicManager { SchematicManager(paths: model.paths, instanceID: instance.id) }
    private var canModify: Bool { !loading && !model.busy && !model.isInstanceInUse(instance.id) }
    private var types: [UTType] { SchematicManager.fileExtensions.map { UTType(filenameExtension: $0) ?? .data } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: "原理图", subtitle: instance.name)
                Spacer()
                Button("新建文件夹", systemImage: "folder.badge.plus") { folderName = ""; creatingFolder = true }.disabled(!canModify)
                Button("导入…", systemImage: "square.and.arrow.down") { importing = true }.disabled(!canModify)
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }
            Text("文件保存在当前运行目录的 schematics 文件夹，供 Litematica、WorldEdit 等模组使用。").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button { directory = directory.split(separator: "/").dropLast().joined(separator: "/"); search = "" } label: { Image(systemName: "chevron.left") }.disabled(directory.isEmpty || model.busy).help("返回上一级")
                Button("schematics") { directory = ""; search = "" }.disabled(directory.isEmpty || model.busy)
                if !directory.isEmpty { Text("/ " + directory).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary) }
                Spacer()
                TextField("搜索当前文件夹", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                List(entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "square.3.layers.3d").font(.title2).foregroundStyle(Theme.accent)
                        Button {
                            if entry.isDirectory { directory = entry.id; search = "" } else { inspecting = entry }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.name).font(.headline).lineLimit(1)
                                if !entry.isDirectory { Text(entry.url.pathExtension.uppercased() + " · " + ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.busy)
                        Menu {
                            if !entry.isDirectory { Button("查看信息") { inspecting = entry }; Button("导出…") { export(entry) }.disabled(!canModify) }
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                            Divider()
                            Button("移到废纸篓…", role: .destructive) { removing = entry }.disabled(!canModify)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.padding(.vertical, 7)
                }.listStyle(.bordered)
                .overlay { if entries.isEmpty { Text("将原理图拖到这里，或点击“导入”。").foregroundStyle(.secondary).allowsHitTesting(false) } }
                .dropDestination(for: URL.self) { urls, _ in guard canModify else { return false }; importFiles(urls); return true }
            }
            HStack {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await reload() } }.disabled(loading || model.busy)
                Spacer()
                if model.busy { ProgressView().controlSize(.small); Button("取消任务") { model.operation?.cancel() } }
            }
        }.padding(24).frame(width: 780, height: 600).interactiveDismissDisabled(model.busy)
        .task(id: directory) { await reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: types, allowsMultipleSelection: true) { result in
            do { importFiles(try result.get()) } catch { self.error = error.localizedDescription }
        }
        .sheet(item: $inspecting) { entry in SchematicInfoView(entry: entry, manager: manager) }
        .alert("新建文件夹", isPresented: $creatingFolder) {
            TextField("文件夹名称", text: $folderName)
            Button("创建") { mutate("新建原理图文件夹") { try await manager.createFolder(folderName, directory: directory) } }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("移到废纸篓？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("移到废纸篓", role: .destructive) {
                if let entry = removing { mutate("移除原理图") { _ = try await manager.remove(entry) } }
                removing = nil
            }
        } message: { Text((removing?.name ?? "") + (removing?.isDirectory == true ? " 及其中的全部文件" : "")) }
    }
    private func importFiles(_ urls: [URL]) {
        mutate("导入原理图") {
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }; defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            try await manager.importFiles(urls, directory: directory)
        }
    }
    private func export(_ entry: SchematicEntry) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = entry.name
        panel.allowedContentTypes = [UTType(filenameExtension: entry.url.pathExtension) ?? .data]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        mutate("导出原理图") { try await manager.export(entry, to: destination); model.notice = "原理图已导出"; model.noticeFileURL = destination }
    }
    private func reload() async {
        loading = true; error = nil
        do { let value = try await manager.list(directory: directory); try Task.checkCancellation(); entries = value }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        loading = false
    }
    private func mutate(_ title: String, action: @MainActor @Sendable @escaping () async throws -> Void) {
        guard canModify else { return }; error = nil
        model.perform(title, presentErrors: false, instanceID: instance.id) { _ in
            do { try await action(); await reload() }
            catch { self.error = error.localizedDescription; throw error }
        }
    }
}

private struct SchematicInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: SchematicEntry
    let manager: SchematicManager
    @State private var info: SchematicInfo?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: info?.name?.isEmpty == false ? info!.name! : entry.name, subtitle: entry.name)
            if let info {
                if let data = info.previewARGB, let preview = image(data) { Image(nsImage: preview).resizable().interpolation(.none).scaledToFit().frame(maxWidth: .infinity, maxHeight: 160) }
                if let description = info.description, !description.isEmpty { Text(description).font(.callout).textSelection(.enabled) }
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                    if let author = info.author, !author.isEmpty { row("作者", author) }
                    if !info.dimensions.isEmpty { row("尺寸", info.dimensions.map(String.init).joined(separator: " × ")) }
                    if let blocks = info.blocks { row("方块数", blocks.formatted()) }
                    if let volume = info.volume { row("总体积", volume.formatted()) }
                    if let regions = info.regions { row("区域数", regions.formatted()) }
                    if let version = info.formatVersion { row("格式版本", String(version)) }
                    if let version = info.gameDataVersion { row("游戏数据版本", String(version)) }
                    if let date = info.createdAt { row("创建时间", date.formatted(date: .abbreviated, time: .shortened)) }
                    if let date = info.modifiedAt { row("修改时间", date.formatted(date: .abbreviated, time: .shortened)) }
                    row("文件大小", ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                }
            } else if let error { Text("无法预览信息：" + error).font(.callout).foregroundStyle(.orange) }
            else { ProgressView("读取原理图信息…") }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 580)
        .task { do { info = try await manager.info(entry) } catch { self.error = error.localizedDescription } }
    }
    private func row(_ title: String, _ value: String) -> some View { GridRow { Text(title).foregroundStyle(.secondary); Text(value).textSelection(.enabled) } }
    private func image(_ data: Data) -> NSImage? {
        let pixels = data.count / 4, edge = Int(Double(pixels).squareRoot())
        guard edge > 0, edge * edge == pixels, data.count == pixels * 4,
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: edge, height: edge, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue)), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: edge, height: edge))
    }
}
