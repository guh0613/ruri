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
                Picker("加载器", selection: $loader) { ForEach(LoaderKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
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
