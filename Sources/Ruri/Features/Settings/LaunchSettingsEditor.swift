import SwiftUI
import AppKit
import RuriCore

struct LaunchSettingsEditor: View {
    @Binding var overrides: InstanceLaunchOverrides
    let defaults: LaunchSettingsValues
    let runtimes: [JavaRuntime]
    var showsInheritance = true
    var keys = LaunchSettingKey.allCases
    @State private var javaIssue: String?
    private var effective: LaunchSettingsValues { overrides.resolve(defaults: defaults) }

    var body: some View {
        ForEach(keys) { key in
            Section {
                if showsInheritance && overrides.inherits(key) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("跟随默认设置").font(.caption).foregroundStyle(.secondary)
                            Text(summary(key)).lineLimit(3).textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        Button("自定义") { overrides.setInheritance(false, for: key, defaults: defaults) }
                            .accessibilityLabel("自定义\(key.title)")
                    }.padding(.vertical, 3)
                } else { fields(key) }
            } header: {
                HStack {
                    Text(key.title)
                    Spacer()
                    if showsInheritance && !overrides.inherits(key) {
                        Button("恢复默认") { overrides.setInheritance(true, for: key, defaults: defaults) }
                            .buttonStyle(.plain).foregroundStyle(.tint).font(.caption)
                            .accessibilityLabel("\(key.title)恢复默认")
                    }
                }
            }
        }
    }
    private func summary(_ key: LaunchSettingKey) -> String {
        switch key {
        case .java:
            if let major = effective.java.major { return "自动选择 Java \(major)" }
            if let path = effective.java.path { return runtimes.first { $0.path == path }?.label ?? path }
            return "自动选择游戏所需的 Java"
        case .memory:
            return (effective.memory.mode == .automatic ? "自动分配" : "最大 \(effective.memory.maximumMB) MB") + (effective.memory.initialMB.map { " · 初始 \($0) MB" } ?? "")
        case .window: return "\(effective.window.width) × \(effective.window.height)" + (effective.window.fullscreen ? " · 全屏启动" : " · 使用游戏保存的显示模式")
        case .presentation: return effective.presentation.showLogs ? "启动时打开日志" : effective.presentation.hideLauncher ? "游戏运行时隐藏 Ruri" : "保持 Ruri 可见"
        case .jvmArguments: return effective.jvmArguments.isEmpty ? "无附加 JVM 参数" : effective.jvmArguments
        case .gameArguments: return effective.gameArguments.isEmpty ? "无附加游戏参数" : effective.gameArguments
        case .commands: return effective.commands.enabled && !effective.commands.isEmpty ? "已启用自定义启动命令" : "不运行自定义启动命令"
        case .environment:
            guard let environment = try? LaunchEnvironment(effective.environment) else { return "默认环境配置需要修正" }
            return environment.entries.isEmpty ? "无自定义环境变量" : "\(environment.entries.count) 项自定义环境变量"
        }
    }
    @ViewBuilder private func fields(_ key: LaunchSettingKey) -> some View {
        switch key {
        case .memory:
            MemorySettingsEditor(settings: Binding(get: { effective.memory }, set: { overrides.memory = $0 }), jvmArguments: effective.jvmArguments)
        case .java:
            Picker("运行时", selection: Binding(get: { effective.java }, set: { overrides.java = $0; javaIssue = nil })) {
                Text("自动选择兼容版本").tag(JavaSelection.automatic)
                Section("按主版本选择") {
                    ForEach(Array(Set([8, 11, 16, 17, 21, 25] + runtimes.map(\.major) + [effective.java.major].compactMap { $0 })).sorted(), id: \.self) { major in
                        Text("Java \(major)").tag(JavaSelection.major(major))
                    }
                }
                Section("已安装的运行时") {
                    ForEach(runtimes) { Text($0.label + " · " + $0.version).tag(JavaSelection.path($0.path)) }
                    if let path = effective.java.path, !runtimes.contains(where: { $0.path == path }) { Text("自选：" + path).tag(JavaSelection.path(path)) }
                }
            }
            if let major = effective.java.major {
                SettingsNumberField(title: "Java 主版本", value: Binding(get: { effective.java.major ?? major }, set: { overrides.java = .major($0) }), unit: "")
                Text("缺少此版本时尝试从 Mojang 下载；不符合游戏或整合包要求时会提示。").font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("本地 Java") { Button("选择文件或 JDK…", action: chooseJava) }
            if let path = effective.java.path { Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).truncationMode(.middle) }
            if let javaIssue { Text(javaIssue).font(.caption).foregroundStyle(.red) }
        case .jvmArguments:
            SettingsTextArea(title: "附加 JVM 参数", prompt: "在这里输入 JVM 参数", text: Binding(get: { effective.jvmArguments }, set: { overrides.jvmArguments = $0 }))
            Text("用于 Java 虚拟机。通常留空；内存大小请优先在“Java 与内存”中调整。").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("填写示例") {
                Text("-Dfile.encoding=UTF-8").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("多个参数用空格分隔，含空格的值加引号。").font(.caption).foregroundStyle(.secondary)
            }
        case .gameArguments:
            SettingsTextArea(title: "附加游戏参数", prompt: "在这里输入游戏参数", text: Binding(get: { effective.gameArguments }, set: { overrides.gameArguments = $0 }))
            Text("传给 Minecraft 的额外启动选项。通常留空；窗口尺寸可直接在“窗口与启动”中设置。").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("填写示例") {
                Text("--width 1600 --height 900").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Text("含空格的参数加引号；这里填写的窗口尺寸优先。").font(.caption).foregroundStyle(.secondary)
            }
        case .window:
            SettingsNumberField(title: "窗口宽度", value: windowBinding(\.width), unit: "px")
            SettingsNumberField(title: "窗口高度", value: windowBinding(\.height), unit: "px")
            HStack {
                Text("常用尺寸"); Spacer()
                Menu("选择尺寸") {
                    ForEach([GameWindowSize(width: 1280, height: 720), .init(width: 1600, height: 900), .init(width: 1920, height: 1080), .init(width: 2560, height: 1440)], id: \.width) { size in
                        Button("\(size.width) × \(size.height)") { var value = effective.window; value.width = size.width; value.height = size.height; overrides.window = value }
                    }
            }.fixedSize()
            }
            Toggle("全屏启动", isOn: windowBinding(\.fullscreen))
            Text("关闭后使用游戏内保存的全屏状态。附加游戏参数中指定的尺寸优先。").font(.caption).foregroundStyle(.secondary)
        case .presentation:
            Toggle("启动时打开游戏日志", isOn: presentationBinding(\.showLogs))
            Toggle("游戏运行时隐藏 Ruri", isOn: presentationBinding(\.hideLauncher)).disabled(effective.presentation.showLogs)
            Text(effective.presentation.showLogs ? "打开日志时，Ruri 保持可见。" : "隐藏后可点击 Dock 图标返回 Ruri，游戏退出后会自动恢复窗口。").font(.caption).foregroundStyle(.secondary)
        case .environment:
            EnvironmentVariablesEditor(text: Binding(get: { effective.environment }, set: { overrides.environment = $0 }))
        case .commands:
            LaunchCommandsEditor(commands: Binding(get: { effective.commands }, set: { overrides.commands = $0 }))
        }
    }
    private func chooseJava() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "选择 java 文件、JDK 包或 Java Home 文件夹。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { overrides.java = .path(try JavaDiscovery.executable(in: url).path); javaIssue = nil }
        catch { javaIssue = error.localizedDescription }
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
        Picker("分配方式", selection: $settings.mode) { Text("自动分配").tag(MemorySettings.Mode.automatic); Text("手动设置").tag(MemorySettings.Mode.manual) }
        if settings.mode == .manual {
            SettingsNumberField(title: "最大内存", value: $settings.maximumMB)
            HStack {
                Text("常用大小"); Spacer()
                Menu("选择内存") { ForEach([2048, 4096, 6144, 8192, 12288, 16384], id: \.self) { value in Button("\(value / 1024) GB") { settings.maximumMB = value } } }.fixedSize()
            }
        } else {
            HStack {
                Text("根据当前可用内存估算，为 macOS 保留余量。").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("重新估算") { availability = .current() }.controlSize(.small)
            }
        }
        switch preview {
        case .success(let memory):
            Text(memory.summary).font(.callout).textSelection(.enabled)
            if memory.maximumSource == .jvmArguments || memory.initialSource == .jvmArguments || memory.metaspaceSource == .jvmArguments {
                Text("部分内存设置被附加 JVM 参数覆盖，请到“参数与环境”查看。").font(.caption).foregroundStyle(.orange)
            }
        case .failure(let error): Text(error.localizedDescription).font(.callout).foregroundStyle(.red)
        }
        DisclosureGroup("高级内存选项") {
            Toggle("指定初始内存", isOn: Binding(get: { settings.initialMB != nil }, set: { settings.initialMB = $0 ? 512 : nil }))
            if settings.initialMB != nil { SettingsNumberField(title: "初始内存", value: Binding(get: { settings.initialMB ?? 512 }, set: { settings.initialMB = $0 })) }
            Toggle("限制类元数据内存", isOn: Binding(get: { settings.metaspaceMB != nil }, set: { settings.metaspaceMB = $0 ? 512 : nil }))
            if settings.metaspaceMB != nil { SettingsNumberField(title: "Metaspace 上限", value: Binding(get: { settings.metaspaceMB ?? 512 }, set: { settings.metaspaceMB = $0 })) }
            Text("初始内存不能大于最大内存。Metaspace 用于加载类，通常无需限制。").font(.caption).foregroundStyle(.secondary)
        }
        Text("1024 MB = 1 GB。这里设置 Java 堆内存，游戏进程还会使用额外的系统内存。").font(.caption).foregroundStyle(.secondary)
    }
}
