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
            Picker("运行时", selection: Binding(get: { effective.java }, set: { overrides.java = $0 })) {
                Text("自动选择兼容版本").tag(JavaSelection.automatic)
                ForEach(Array(Set([8, 11, 16, 17, 21, 25] + runtimes.map(\.major) + [effective.java.major].compactMap { $0 })).sorted(), id: \.self) { major in
                    Text("自动选择 Java \(major)").tag(JavaSelection.major(major))
                }
                ForEach(runtimes) { Text($0.label).tag(JavaSelection.path($0.path)) }
                if let path = effective.java.path, !runtimes.contains(where: { $0.path == path }) { Text("自选：" + path).tag(JavaSelection.path(path)) }
            }
            if let major = effective.java.major {
                TextField("主版本", value: Binding(get: { effective.java.major ?? major }, set: { overrides.java = .major($0) }), format: .number)
                Text("在该主版本中选择已发现的运行时；缺少时尝试下载 Mojang 提供的版本。仍会检查游戏要求、整合包约束和架构。").font(.caption).foregroundStyle(.secondary)
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
            Toggle("全屏启动", isOn: windowBinding(\.fullscreen))
            Text("开启时请求游戏进入全屏；关闭时沿用游戏内保存的全屏状态。").font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("宽度", value: windowBinding(\.width), format: .number)
                TextField("高度", value: windowBinding(\.height), format: .number)
            }
            Menu("常用窗口尺寸") {
                ForEach([GameWindowSize(width: 1280, height: 720), .init(width: 1600, height: 900), .init(width: 1920, height: 1080), .init(width: 2560, height: 1440)], id: \.width) { size in
                    Button("\(size.width) × \(size.height)") { var value = effective.window; value.width = size.width; value.height = size.height; overrides.window = value }
                }
            }
            Text("附加游戏参数中指定的宽度和高度优先。").font(.caption).foregroundStyle(.secondary)
        case .presentation:
            Toggle("启动时自动打开日志", isOn: presentationBinding(\.showLogs))
            Toggle("游戏运行时隐藏启动器", isOn: presentationBinding(\.hideLauncher)).disabled(effective.presentation.showLogs)
            Text(effective.presentation.showLogs ? "自动打开日志时，启动器保持可见。" : "游戏进程启动后隐藏 Ruri，退出后恢复窗口。可随时点击 Dock 图标打开启动器。").font(.caption).foregroundStyle(.secondary)
        case .environment:
            TextField("NAME=value", text: Binding(get: { effective.environment }, set: { overrides.environment = $0 }), axis: .vertical)
                .lineLimit(4...10).font(.system(.body, design: .monospaced))
            Text("每行一项 NAME=value；NAME= 设置空值，只写 NAME 则移除继承值。值原样传入，无需引号，不展开变量。仅作用于游戏进程。").font(.caption).foregroundStyle(.secondary)
            Text("JAVA_HOME、CLASSPATH 和 Java 参数环境变量由 Ruri 管理。本机环境配置不写入导出的整合包。").font(.caption).foregroundStyle(.secondary)
            if case .failure(let error) = Result(catching: { try LaunchEnvironment(effective.environment) }) {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }
    private func windowBinding<Value>(_ key: WritableKeyPath<GameWindowSize, Value>) -> Binding<Value> {
        Binding(get: { effective.window[keyPath: key] }, set: { var value = effective.window; value[keyPath: key] = $0; overrides.window = value })
    }
    private func presentationBinding<Value>(_ key: WritableKeyPath<LaunchPresentation, Value>) -> Binding<Value> {
        Binding(get: { effective.presentation[keyPath: key] }, set: { var value = effective.presentation; value[keyPath: key] = $0; overrides.presentation = value })
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
