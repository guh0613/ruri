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
    /// The scanned content of the edited instance; nil while scanning or when
    /// editing the global defaults, which have no instance to inspect.
    var memoryWorkload: MemoryWorkload? = nil
    var scansContent = false
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
                    if showsInheritance && !overrides.inherits(key) {
                        Button(Messages.AppLaunchSettingsEditor.restoreDefault.localized, systemImage: "arrow.uturn.backward") {
                            overrides.setInheritance(true, for: key, defaults: defaults)
                            if key == .java { javaIssue = nil }
                        }
                        .buttonStyle(.link).labelStyle(.titleAndIcon)
                        .font(.caption).fontWeight(.regular).foregroundStyle(Color.accentColor)
                        .accessibilityLabel(Messages.AppLaunchSettingsEditor.restoreDefaultFormat(key.title).localized)
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
        case .macOS: Messages.GameHost.settingsHelp.localized
        case .presentation: effective.presentation.showLogs ? Messages.AppLaunchSettingsEditor.logsKeepLauncherVisible.localized : Messages.AppLaunchSettingsEditor.logsHideLauncherVisible.localized
        default: nil
        }
    }
    @ViewBuilder private func fields(_ key: LaunchSettingKey) -> some View {
        switch key {
        case .memory:
            MemorySettingsEditor(settings: Binding(get: { effective.memory }, set: { overrides.memory = $0 }), jvmArguments: effective.jvmArguments,
                                 workload: memoryWorkload, scansContent: scansContent)
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
            Toggle(Messages.MonitorLogging.debugMode.localized, isOn: presentationBinding(\.debugLogging))
            Text(Messages.MonitorLogging.debugModeHelp.localized).font(.caption).foregroundStyle(.secondary)
        case .environment:
            EnvironmentVariablesEditor(text: Binding(get: { effective.environment }, set: { overrides.environment = $0 }))
        case .macOS:
            Toggle(Messages.GameHost.enableIntegration.localized, isOn: macOSBinding(\.enabled))
            Toggle(Messages.GameHost.instanceAppearance.localized, isOn: macOSBinding(\.instanceAppearance)).disabled(!effective.macOS.enabled)
            Toggle(Messages.GameHost.nativeFullscreen.localized, isOn: macOSBinding(\.nativeFullscreen)).disabled(!effective.macOS.enabled)
        case .commands:
            LaunchCommandsEditor(commands: Binding(get: { effective.commands }, set: { overrides.commands = $0 }))
        }
    }
    private func macOSBinding(_ key: WritableKeyPath<MacOSGameSettings, Bool>) -> Binding<Bool> {
        Binding(get: { effective.macOS[keyPath: key] }, set: { value in
            var settings = effective.macOS; settings[keyPath: key] = value; overrides.macOS = settings
        })
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
    var workload: MemoryWorkload? = nil
    var scansContent = false
    @State private var availability = MemoryAvailability.current()
    private var preview: Result<LaunchMemory, Error> { Result { try JVMHeapArguments.resolve(base: settings.resolve(availability: availability, workload: workload), arguments: ArgumentTokenizer.split(jvmArguments)) } }
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
                if settings.mode == .automatic, let estimate = memory.estimate, memory.maximumSource == .automatic {
                    MemoryEstimateCard(memory: memory, estimate: estimate, scanning: scansContent && workload == nil, scansContent: scansContent) { availability = .current() }
                } else {
                    Text(memory.summary).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if memory.maximumSource == .jvmArguments || memory.initialSource == .jvmArguments || memory.metaspaceSource == .jvmArguments {
                    Label(Messages.AppLaunchSettingsEditor.initialMemoryField.localized, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
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

/// The automatic estimate as a figure, a bar and a row of facts rather than
/// a paragraph: the number the game will get, how much of that is basic
/// demand versus comfort margin against what the machine allows, and the
/// inputs it came from. The reasoning lives behind an info button.
struct MemoryEstimateCard: View {
    let memory: LaunchMemory
    let estimate: MemoryEstimate
    let scanning: Bool
    let scansContent: Bool
    let reestimate: () -> Void
    @State private var explaining = false

    private func size(_ megabytes: Int) -> String { LocalizedFormat.bytes(Int64(megabytes) * 1_048_576, memory: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(size(memory.maximumMB))
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(estimate.constrained ? Color.orange : Color.primary)
                    Text(Messages.AppLaunchSettingsEditor.heapLimit.localized + " · " + Messages.AppLaunchSettingsEditor.initialHeapValue(size(Int(memory.initialBytes / 1_048_576))).localized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button { explaining.toggle() } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help(Messages.AppLaunchSettingsEditor.memoryEstimateExplain.localized)
                    .accessibilityLabel(Messages.AppLaunchSettingsEditor.memoryEstimateExplain.localized)
                    .popover(isPresented: $explaining, arrowEdge: .bottom) {
                        Text((scansContent ? Messages.AppLaunchSettingsEditor.memoryEstimateHelp : Messages.AppLaunchSettingsEditor.memoryEstimateGenericHelp).localized)
                            .font(.callout).multilineTextAlignment(.leading).frame(width: 320, alignment: .leading).padding(16)
                    }
                Button(Messages.AppLaunchSettingsEditor.reestimateMemory.localized, systemImage: "arrow.clockwise", action: reestimate)
                    .controlSize(.small)
            }
            bar
            facts
            if estimate.constrained {
                status(Messages.AppLaunchSettingsEditor.memoryEstimateShortfall(size(estimate.demandMB), size(estimate.maximumMB)).localized, symbol: "exclamationmark.triangle.fill", tint: .orange)
            } else if estimate.trimmed {
                status(Messages.AppLaunchSettingsEditor.memoryEstimateTrimmed(size(estimate.demandMB), size(estimate.generousMB)).localized, symbol: "info.circle", tint: .secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    /// Track is what the machine allows; the filled part is the heap, split into
    /// basic demand and margin. Demand the machine cannot cover shows as a
    /// faint orange tail so the shortfall is visible at a glance.
    private var bar: some View {
        let track = max(estimate.ceilingMB, estimate.generousMB, estimate.demandMB, 1)
        let granted = min(estimate.maximumMB, estimate.demandMB), margin = max(0, estimate.maximumMB - estimate.demandMB), unmet = max(0, estimate.demandMB - estimate.maximumMB)
        let tint: Color = estimate.constrained ? .orange : Theme.accent
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                let unit = geometry.size.width / CGFloat(track)
                HStack(spacing: 2) {
                    Capsule().fill(tint.gradient).frame(width: max(4, unit * CGFloat(granted)))
                    if margin > 0 { Capsule().fill(tint.opacity(0.4)).frame(width: max(3, unit * CGFloat(margin))) }
                    if unmet > 0 { Capsule().fill(Color.orange.opacity(0.28)).frame(width: max(3, unit * CGFloat(unmet))) }
                    Spacer(minLength: 0)
                }
                .background(Capsule().fill(.primary.opacity(0.08)))
            }
            .frame(height: 7)
            .accessibilityHidden(true)
            HStack(spacing: 14) {
                legend(Messages.AppLaunchSettingsEditor.estimateDemandLegend.localized, value: size(estimate.demandMB), color: tint)
                if margin > 0 { legend(Messages.AppLaunchSettingsEditor.estimateMarginLegend.localized, value: size(margin), color: tint.opacity(0.4)) }
                if unmet > 0 { legend(Messages.AppLaunchSettingsEditor.estimateUnmetLegend.localized, value: size(unmet), color: .orange.opacity(0.28)) }
                Spacer(minLength: 0)
                Text(Messages.AppLaunchSettingsEditor.estimateCeilingLegend(size(estimate.ceilingMB)).localized).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func legend(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }.font(.caption2)
    }

    @ViewBuilder private var facts: some View {
        if scanning {
            Label(Messages.AppLaunchSettingsEditor.memoryEstimateScanning.localized, systemImage: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                if estimate.workload.scanned {
                    chip(estimate.workload.gameVersion, symbol: "cube")
                    chip(estimate.workload.loader.title, symbol: estimate.workload.loader.symbol)
                    chip(Messages.CoreMemoryEstimate.modCount(Int64(estimate.workload.modCount)).localized, symbol: "shippingbox")
                } else {
                    chip(Messages.AppLaunchSettingsEditor.memoryEstimateSample.localized, symbol: "cube")
                }
                if let available = estimate.availability.availableMB {
                    chip(Messages.CoreMemoryEstimate.availableMemory(size(available)).localized, symbol: "memorychip")
                }
            }
        }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium)).labelStyle(.titleAndIcon)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(.secondary).lineLimit(1)
    }

    private func status(_ text: String, symbol: String, tint: Color) -> some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
            .font(.caption).foregroundStyle(tint)
    }
}
