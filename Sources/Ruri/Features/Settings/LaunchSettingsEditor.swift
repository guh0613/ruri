import RuriLocalization
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
                fields(key)
            } header: {
                HStack {
                    Text(key.title)
                    Spacer()
                    if showsInheritance {
                        if overrides.inherits(key) {
                            Text(Messages.AppLaunchSettingsEditor.followDefault.localized)
                                .font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
                        } else {
                            Button(Messages.AppLaunchSettingsEditor.restoreDefault.localized) {
                                overrides.setInheritance(true, for: key, defaults: defaults)
                                if key == .java { javaIssue = nil }
                            }
                            .buttonStyle(.borderless).font(.caption).fontWeight(.regular)
                            .accessibilityLabel(Messages.AppLaunchSettingsEditor.restoreDefaultFormat(key.title).localized)
                        }
                    }
                }
            } footer: {
                if let help = sectionHelp(key) { Text(help).fixedSize(horizontal: false, vertical: true) }
            }.id(key)
        }
    }
    private func sectionHelp(_ key: LaunchSettingKey) -> String? {
        switch key {
        case .java: effective.java.major == nil ? nil : Messages.AppLaunchSettingsEditor.javaRuntimeHelp.localized
        case .memory: Messages.AppLaunchSettingsEditor.heapMemoryExplanation.localized
        case .window: Messages.AppLaunchSettingsEditor.fullscreenHelp.localized
        case .presentation: effective.presentation.showLogs ? Messages.AppLaunchSettingsEditor.logsKeepLauncherVisible.localized : Messages.AppLaunchSettingsEditor.logsHideLauncherVisible.localized
        default: nil
        }
    }
    @ViewBuilder private func fields(_ key: LaunchSettingKey) -> some View {
        switch key {
        case .memory:
            MemorySettingsEditor(settings: Binding(get: { effective.memory }, set: { overrides.memory = $0 }), jvmArguments: effective.jvmArguments)
        case .java:
            Picker(Messages.AppLaunchSettingsEditor.runtime.localized, selection: Binding(get: { effective.java }, set: { overrides.java = $0; javaIssue = nil })) {
                Text(Messages.AppLaunchSettingsEditor.autoCompatibleRuntime.localized).tag(JavaSelection.automatic)
                Section(Messages.AppLaunchSettingsEditor.majorVersionRuntime.localized) {
                    ForEach(Array(Set([8, 11, 16, 17, 21, 25] + runtimes.map(\.major) + [effective.java.major].compactMap { $0 })).sorted(), id: \.self) { major in
                        Text("Java \(major)").tag(JavaSelection.major(major))
                    }
                }
                Section(Messages.AppLaunchSettingsEditor.installedRuntime.localized) {
                    ForEach(runtimes) { Text($0.label + " · " + $0.version).tag(JavaSelection.path($0.path)) }
                    if let path = effective.java.path, !runtimes.contains(where: { $0.path == path }) { Text(Messages.AppLaunchSettingsEditor.unavailableJavaPath(path).localized).tag(JavaSelection.path(path)) }
                }
            }
            if let major = effective.java.major {
                SettingsNumberField(title: Messages.AppLaunchSettingsEditor.javaMajorVersion.localized, value: Binding(get: { effective.java.major ?? major }, set: { overrides.java = .major($0) }), unit: "")
            }
            LabeledContent(Messages.AppLaunchSettingsEditor.localJava.localized) { Button(Messages.AppLaunchSettingsEditor.chooseJavaFile.localized, action: chooseJava) }
            if let path = effective.java.path { Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).truncationMode(.middle) }
            if let javaIssue { Text(javaIssue).font(.caption).foregroundStyle(.red) }
        case .jvmArguments:
            SettingsTextArea(title: Messages.AppLaunchSettingsEditor.jvmArguments.localized,
                             prompt: Messages.AppLaunchSettingsEditor.jvmArgumentsPlaceholder.localized,
                             text: Binding(get: { effective.jvmArguments }, set: { overrides.jvmArguments = $0 }),
                             help: Messages.AppLaunchSettingsEditor.jvmArgumentsHelp.localized)
        case .gameArguments:
            SettingsTextArea(title: Messages.AppLaunchSettingsEditor.gameArguments.localized,
                             prompt: Messages.AppLaunchSettingsEditor.gameArgumentsPlaceholder.localized,
                             text: Binding(get: { effective.gameArguments }, set: { overrides.gameArguments = $0 }),
                             help: Messages.AppLaunchSettingsEditor.gameArgumentsHelp.localized)
        case .window:
            HStack(spacing: 12) {
                Text(Messages.AppLaunchSettingsEditor.windowSize.localized)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    SettingsNumberInput(title: Messages.AppLaunchSettingsEditor.windowWidth.localized, value: windowBinding(\.width), unit: "")
                    Text("×").foregroundStyle(.secondary).fixedSize().accessibilityHidden(true)
                    SettingsNumberInput(title: Messages.AppLaunchSettingsEditor.windowHeight.localized, value: windowBinding(\.height), unit: "px")
                }
                Menu(Messages.AppLaunchSettingsEditor.commonWindowSize.localized) {
                    ForEach([GameWindowSize(width: 1280, height: 720), .init(width: 1600, height: 900), .init(width: 1920, height: 1080), .init(width: 2560, height: 1440)], id: \.width) { size in
                        Button("\(size.width) × \(size.height)") { var value = effective.window; value.width = size.width; value.height = size.height; overrides.window = value }
                    }
                }.fixedSize()
            }
            Toggle(Messages.AppLaunchSettingsEditor.fullscreenOption.localized, isOn: windowBinding(\.fullscreen))
        case .presentation:
            Toggle(Messages.AppLaunchSettingsEditor.openGameLogs.localized, isOn: presentationBinding(\.showLogs))
            Toggle(Messages.AppLaunchSettingsEditor.hideLauncher.localized, isOn: presentationBinding(\.hideLauncher)).disabled(effective.presentation.showLogs)
        case .environment:
            EnvironmentVariablesEditor(text: Binding(get: { effective.environment }, set: { overrides.environment = $0 }))
        case .commands:
            LaunchCommandsEditor(commands: Binding(get: { effective.commands }, set: { overrides.commands = $0 }))
        }
    }
    private func chooseJava() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = Messages.AppLaunchSettingsEditor.chooseJavaPanelHelp.localized
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
        Picker(Messages.AppLaunchSettingsEditor.allocationMethod.localized, selection: $settings.mode) { Text(Messages.AppLaunchSettingsEditor.automaticMemory.localized).tag(MemorySettings.Mode.automatic); Text(Messages.AppLaunchSettingsEditor.manualMemory.localized).tag(MemorySettings.Mode.manual) }
        if settings.mode == .manual {
            HStack(spacing: 12) {
                Text(Messages.AppLaunchSettingsEditor.maximumMemoryLabel.localized)
                Spacer(minLength: 8)
                SettingsNumberInput(title: Messages.AppLaunchSettingsEditor.maximumMemoryLabel.localized, value: $settings.maximumMB)
                Menu(Messages.AppLaunchSettingsEditor.commonMemorySize.localized) {
                    ForEach([2048, 4096, 6144, 8192, 12288, 16384], id: \.self) { value in
                        Button(LocalizedFormat.bytes(Int64(value) * 1_048_576, memory: true)) { settings.maximumMB = value }
                    }
                }.fixedSize()
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            switch preview {
            case .success(let memory):
                HStack {
                    Text(memory.summary).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if settings.mode == .automatic {
                        Button(Messages.AppLaunchSettingsEditor.reestimateMemory.localized) { availability = .current() }.controlSize(.small)
                    }
                }
                if settings.mode == .automatic {
                    Text(Messages.AppLaunchSettingsEditor.memoryEstimateHelp.localized).font(.caption).foregroundStyle(.secondary)
                }
                if memory.maximumSource == .jvmArguments || memory.initialSource == .jvmArguments || memory.metaspaceSource == .jvmArguments {
                    Text(Messages.AppLaunchSettingsEditor.initialMemoryField.localized).font(.caption).foregroundStyle(.orange)
                }
            case .failure(let error): Text(error.localizedDescription).font(.callout).foregroundStyle(.red)
            }
        }
        DisclosureGroup(Messages.AppLaunchSettingsEditor.advancedMemory.localized) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(Messages.AppLaunchSettingsEditor.initialMemoryToggle.localized, isOn: Binding(get: { settings.initialMB != nil }, set: { settings.initialMB = $0 ? 512 : nil }))
                    if settings.initialMB != nil {
                        SettingsNumberField(title: Messages.AppLaunchSettingsEditor.initialMemory.localized, value: Binding(get: { settings.initialMB ?? 512 }, set: { settings.initialMB = $0 }))
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(Messages.AppLaunchSettingsEditor.metaspaceToggle.localized, isOn: Binding(get: { settings.metaspaceMB != nil }, set: { settings.metaspaceMB = $0 ? 512 : nil }))
                    if settings.metaspaceMB != nil {
                        SettingsNumberField(title: Messages.AppLaunchSettingsEditor.metaspaceLimit.localized, value: Binding(get: { settings.metaspaceMB ?? 512 }, set: { settings.metaspaceMB = $0 }))
                    }
                }
                Text(Messages.AppLaunchSettingsEditor.memorySettingsHelp.localized).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }.multilineTextAlignment(.leading).padding(.top, 12).padding(.bottom, 6)
        }
    }
}
