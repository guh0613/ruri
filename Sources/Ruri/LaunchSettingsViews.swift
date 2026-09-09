import SwiftUI
import AppKit
import RuriCore

struct LaunchSettingsEditor: View {
    @Binding var overrides: InstanceLaunchOverrides
    let defaults: LaunchSettingsValues
    let runtimes: [JavaRuntime]
    var showsInheritance = true
    private var effective: LaunchSettingsValues { overrides.resolve(defaults: defaults) }

    var body: some View {
        ForEach(LaunchSettingKey.allCases) { key in
            Section(key.title) {
                if showsInheritance {
                    Toggle("跟随默认设置", isOn: Binding(get: { overrides.inherits(key) }, set: { overrides.setInheritance($0, for: key, defaults: defaults) }))
                    Text(overrides.inherits(key) ? "下方显示当前生效的默认值；以后修改默认设置时会一起更新。" : "此项由该实例单独设置。").font(.caption).foregroundStyle(.secondary)
                }
                fields(key).disabled(showsInheritance && overrides.inherits(key))
            }
        }
    }
    @ViewBuilder private func fields(_ key: LaunchSettingKey) -> some View {
        switch key {
        case .memory:
            MemorySettingsEditor(settings: Binding(get: { effective.memory }, set: { overrides.memory = $0 }), jvmArguments: effective.jvmArguments)
        case .java:
            Picker("运行时", selection: Binding(get: { effective.java.path ?? "" }, set: { overrides.java = $0.isEmpty ? .automatic : .path($0) })) {
                Text("自动选择兼容版本").tag("")
                ForEach(runtimes) { Text($0.label).tag($0.path) }
                if let path = effective.java.path, !runtimes.contains(where: { $0.path == path }) { Text("自选：" + path).tag(path) }
            }
            if let path = effective.java.path { Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Button("选择 Java 可执行文件…", systemImage: "folder") {
                let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
                panel.message = "选择 Java 安装目录内的 bin/java；启动时会检查版本和架构。"
                if panel.runModal() == .OK, let url = panel.url { overrides.java = .path(url.path) }
            }
        case .jvmArguments:
            TextField("例如 -Dfile.encoding=UTF-8", text: Binding(get: { effective.jvmArguments }, set: { overrides.jvmArguments = $0 }), axis: .vertical).lineLimit(2...4).font(.system(.body, design: .monospaced))
            Text("不跟随默认且留空时，不添加默认的附加 JVM 参数。").font(.caption).foregroundStyle(.secondary)
        case .gameArguments:
            TextField("附加游戏参数", text: Binding(get: { effective.gameArguments }, set: { overrides.gameArguments = $0 }), axis: .vertical).lineLimit(2...4).font(.system(.body, design: .monospaced))
            Text("含空格的参数请加引号；参数直接传给游戏。").font(.caption).foregroundStyle(.secondary)
        case .window:
            TextField("宽度", value: Binding(get: { effective.window.width }, set: { overrides.window = .init(width: $0, height: effective.window.height) }), format: .number)
            TextField("高度", value: Binding(get: { effective.window.height }, set: { overrides.window = .init(width: effective.window.width, height: $0) }), format: .number)
        }
    }
}

struct MemorySettingsEditor: View {
    @Binding var settings: MemorySettings
    let jvmArguments: String
    @State private var availability = MemoryAvailability.current()
    private var preview: Result<LaunchMemory, Error> { Result { try JVMHeapArguments.resolve(base: settings.resolve(availability: availability), arguments: ArgumentTokenizer.split(jvmArguments)) } }
    var body: some View {
        Picker("分配方式", selection: $settings.mode) { Text("自动估算").tag(MemorySettings.Mode.automatic); Text("手动设置").tag(MemorySettings.Mode.manual) }.pickerStyle(.segmented)
        if settings.mode == .manual {
            HStack {
                TextField("最大堆（MB）", value: $settings.maximumMB, format: .number)
                Menu("常用内存") { ForEach([2048, 4096, 6144, 8192, 12288, 16384], id: \.self) { value in Button("\(value / 1024) GB") { settings.maximumMB = value } } }.fixedSize()
            }
        } else {
            Text("根据物理内存与当前可用估算，为系统保留余量；本轮上限在开始启动时固定。大型整合包可按需要手动调整。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("物理内存 \(availability.physicalMB) MB" + (availability.availableMB.map { " · 可用估算 \($0) MB" } ?? ""))
                Spacer(); Button("重新估算") { availability = .current() }
            }.font(.caption)
        }
        DisclosureGroup("初始堆与类元数据") {
            Toggle("指定最小与初始堆", isOn: Binding(get: { settings.initialMB != nil }, set: { settings.initialMB = $0 ? 512 : nil }))
            if settings.initialMB != nil { TextField("初始堆（MB）", value: Binding(get: { settings.initialMB ?? 512 }, set: { settings.initialMB = $0 }), format: .number) }
            Toggle("限制 Metaspace", isOn: Binding(get: { settings.metaspaceMB != nil }, set: { settings.metaspaceMB = $0 ? 512 : nil }))
            if settings.metaspaceMB != nil { TextField("类元数据上限（MB）", value: Binding(get: { settings.metaspaceMB ?? 512 }, set: { settings.metaspaceMB = $0 }), format: .number) }
            Text("Metaspace 位于 Java 堆之外，用于加载类。默认不额外限制；过小的上限可能导致模组加载失败。").font(.caption).foregroundStyle(.secondary)
        }
        switch preview {
        case .success(let memory):
            Text(memory.summary).font(.callout).textSelection(.enabled)
            if memory.maximumSource == .jvmArguments || memory.initialSource == .jvmArguments || memory.metaspaceSource == .jvmArguments {
                Text("附加 JVM 参数按出现顺序覆盖内存设置，最后一项生效。堆上限来源：\(memory.maximumSource.title)；初始堆来源：\(memory.initialSource.title)。").font(.caption).foregroundStyle(.secondary)
            }
        case .failure(let error): Text(error.localizedDescription).font(.callout).foregroundStyle(.red)
        }
        Text("上限针对 Java 堆，不代表游戏进程的总内存占用。1024 MB = 1 GB。").font(.caption).foregroundStyle(.secondary)
    }
}

struct DefaultLaunchSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var overrides: InstanceLaunchOverrides
    @State private var issue: String?
    private let original: LaunchSettingsValues
    init(settings: AppSettings) {
        original = settings.defaultLaunchSettings
        _overrides = State(initialValue: .init(fixing: settings.defaultLaunchSettings))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "默认启动设置", subtitle: "用于跟随默认设置的项目；已运行的游戏保持本次启动时的值。")
            Text("新建实例默认继承。旧实例和导入实例保留原值，可在实例设置中按项恢复默认。").font(.callout).foregroundStyle(.secondary)
            Form { LaunchSettingsEditor(overrides: $overrides, defaults: original, runtimes: model.runtimes, showsInheritance: false) }.formStyle(.grouped)
            if let issue { Text(issue).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存默认设置") {
                    do { let values = overrides.resolve(defaults: original); try values.validate(); model.updateDefaultLaunchSettings(values, basedOn: original); dismiss() }
                    catch { issue = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620, height: 590)
    }
}
