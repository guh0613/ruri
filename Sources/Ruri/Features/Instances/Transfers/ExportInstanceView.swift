import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ExportInstanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var format = InstanceExportFormat.ruri
    @State private var includeWorlds = true
    @State private var details = ModpackExportDetails()
    private var localInstallation: Bool { instance.repositoryVersionID != nil || instance.importedInstallation != nil }
    private var complete: Bool { format == .complete || (format == .ruri && localInstallation) }
    private var formats: [InstanceExportFormat] { localInstallation ? [.complete] : InstanceExportFormat.allCases }
    init(instance: GameInstance) {
        self.instance = instance
        _format = State(initialValue: instance.repositoryVersionID != nil || instance.importedInstallation != nil ? .complete : .ruri)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("导出 \(instance.name)", systemImage: "square.and.arrow.up").font(.title2.bold())
            Text(complete ? "将当前客户端、依赖、资源、模组和配置一起保存为 ZIP。导入时直接还原这些文件，保留本地修改；Java 运行时另行选择。" : "将模组、配置与游戏设置保存为可迁移的 ZIP。设置按导出时的生效值保存；导入后不依赖这台 Mac 的默认值，游戏依赖会重新下载。").foregroundStyle(.secondary)
            Picker("导出格式", selection: $format) { ForEach(formats) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            if format == .mcbbs || format == .mrpack {
                LabeledContent("版本") { TextField("整合包版本", text: $details.version).textFieldStyle(.roundedBorder) }
                if format == .mcbbs { LabeledContent("作者") { TextField("作者", text: $details.author).textFieldStyle(.roundedBorder) } }
                TextField("描述", text: $details.description, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
            }
            if format == .mrpack { Toggle("从 Modrinth 引用可下载文件", isOn: $details.referenceDownloads) }
            Toggle("包含存档", isOn: $includeWorlds)
            if !instance.resolvedLaunchSettings(defaults: model.state.settings).environment.isEmpty {
                Text("本机环境变量不包含在导出文件中。").font(.caption).foregroundStyle(.secondary)
            }
            if instance.resolvedLaunchSettings(defaults: model.state.settings).java.major != nil, format != .ruri && format != .complete {
                Text("指定的 Java 主版本仅在 Ruri 格式中保留。").font(.caption).foregroundStyle(.secondary)
            }
            Text(complete ? "完整副本保留模组来源、组件信息与当前 macOS 安装文件，适合备份和迁移到相同游戏架构的 Mac。日志、账号、Java 和游玩历史不包含在内。" : format == .ruri ? "Ruri 格式还会保留模组来源与版本记录，方便继续检查更新。" : format == .mcbbs ? "可在 HMCL 中导入，包含文件校验、游戏版本、加载器、内存要求和启动参数。" : format == .mrpack ? "已识别的 Modrinth 文件写入下载清单；其他文件内附。mrpack 不保存启动器的内存与窗口设置，附加启动参数请使用 MCBBS 或 Ruri 格式。" : "可通过 Prism 或 MultiMC 的实例导入功能打开。跨平台迁移后，部分模组可能需要重新配置。").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("选择保存位置…") { chooseDestination() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || model.isInstanceInUse(instance.id))
            }
        }.padding(26).frame(width: 510)
    }
    private func chooseDestination() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [format == .mrpack ? (UTType(filenameExtension: "mrpack") ?? .zip) : .zip]
        panel.nameFieldStringValue = instance.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + (format == .mrpack ? ".mrpack" : ".zip")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(instance, to: url, format: format, includeWorlds: includeWorlds, details: details); dismiss()
    }
}
