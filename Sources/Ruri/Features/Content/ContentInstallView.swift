import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ContentInstallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: ModrinthProject
    @State private var versions: [ModrinthVersion] = []
    @State private var selectedVersion = ""
    @State private var instanceID: UUID?
    @State private var loading = false
    @State private var error: String?
    private let service = ModrinthService()
    var instance: GameInstance? { model.state.instances.first { $0.id == instanceID } }
    var isPack: Bool { project.project_type == "modpack" }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: project.title, subtitle: "by \(project.author)")
            Text(project.description).font(.callout).foregroundStyle(.secondary).lineLimit(5)
            if !isPack {
                Picker("安装到实例", selection: $instanceID) {
                    Text("选择一个实例").tag(nil as UUID?)
                    ForEach(model.state.instances.filter(\.installed)) { Text($0.name + " · " + $0.subtitle).tag(Optional($0.id)) }
                }
            }
            if loading { ProgressView("查找兼容版本…") }
            else if !versions.isEmpty {
                Picker("内容版本", selection: $selectedVersion) { ForEach(versions) { Text($0.name).tag($0.id) } }
            } else { Text(isPack || instance != nil ? "没有兼容的版本。" : "请先选择已安装的游戏实例。").foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            if project.project_type == "shader" { Text("光影文件会放入 shaderpacks。请确保实例已经安装 Iris 或其他兼容的光影加载模组。").font(.caption).foregroundStyle(.secondary) }
            if project.project_type == "mod" { Text("会自动解析并安装此版本的必需依赖。").font(.caption).foregroundStyle(.secondary) }
            HStack {
                if let page = project.pageURL { Link("在 Modrinth 查看", destination: page) }
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isPack ? "查看整合包" : "安装") {
                    guard let version = versions.first(where: { $0.id == selectedVersion }) else { return }
                    model.installContent(project: project, version: version, instance: instance); dismiss()
                }.buttonStyle(.borderedProminent).disabled(loading || selectedVersion.isEmpty || model.busy || (!isPack && (instance == nil || model.isInstanceInUse(instanceID))))
            }
        }.padding(30).frame(width: 570)
        .onAppear { instanceID = model.selected?.id }
        .task(id: instanceID) {
            versions = []; selectedVersion = ""; error = nil
            guard isPack || instance != nil else { return }
            loading = true
            do {
                let result = try await service.versions(project: project.id, game: isPack ? nil : instance?.gameVersion, loader: project.project_type == "mod" ? instance?.loader.rawValue : nil)
                try Task.checkCancellation(); versions = result; selectedVersion = result.first?.id ?? ""
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            loading = false
        }
    }
}
