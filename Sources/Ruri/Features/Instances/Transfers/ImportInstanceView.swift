import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ImportInstanceView: View {
    @Environment(AppModel.self) private var model
    let prepared: PreparedInstanceImport
    let updateTarget: GameInstance?
    let onPreparedUpdate: (@MainActor @Sendable (PreparedModpackUpdate) -> Void)?
    let onCancel: (@MainActor @Sendable () -> Void)?
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
    init(prepared: PreparedInstanceImport, updateTarget: GameInstance? = nil, onPreparedUpdate: (@MainActor @Sendable (PreparedModpackUpdate) -> Void)? = nil, onCancel: (@MainActor @Sendable () -> Void)? = nil) {
        self.prepared = prepared; self.updateTarget = updateTarget; self.onPreparedUpdate = onPreparedUpdate; self.onCancel = onCancel
        _name = State(initialValue: prepared.instance.name); _keepJVMArguments = State(initialValue: prepared.format == "MCBBS" || prepared.includesInstallation); _excludedOptional = State(initialValue: prepared.omittedOptionalPaths)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(updateTarget == nil ? Messages.AppImportInstanceView.bodyText1.localized : Messages.AppImportInstanceView.bodyText2.localized, systemImage: "square.and.arrow.down").font(.title2.bold())
            if let updateTarget { Text(Messages.AppImportInstanceView.updateTarget(updateTarget.name).localized).font(.callout).foregroundStyle(.secondary) }
            else {
                Label(Messages.AppImportInstanceView.updateTargetText3(String(describing: model.selectedDirectoryName)).localized, systemImage: "folder").font(.callout).foregroundStyle(.secondary)
                Text(Messages.AppImportInstanceView.updateTargetText4.localized).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(prepared.includesInstallation ? Messages.AppImportInstanceView.updateTargetText5.localized : Messages.AppImportInstanceView.updateTargetText6(String(describing: prepared.format)).localized).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        if updateTarget == nil { LabeledContent(Messages.AppImportInstanceView.updateTargetText7.localized) { TextField(Messages.AppImportInstanceView.updateTargetText7.localized, text: $name).textFieldStyle(.roundedBorder) } }
                        LabeledContent(Messages.AppImportInstanceView.updateTargetText8.localized, value: prepared.instance.subtitle)
                        LabeledContent(Messages.AppImportInstanceView.updateTargetText9.localized, value: "\(prepared.instance.memoryMB) MB")
                        LabeledContent(Messages.AppImportInstanceView.updateTargetText10.localized, value: "\(prepared.instance.width) × \(prepared.instance.height)")
                        if let java = prepared.instance.supportedJavaMajors, !java.isEmpty { LabeledContent(Messages.AppImportInstanceView.javaText1.localized, value: LocalizedFormat.list(java.map(String.init))) }
                        if selectedImport.remoteFileCount > 0 { LabeledContent(Messages.AppImportInstanceView.javaText2.localized, value: Messages.AppImportInstanceView.javaText3(Int64(selectedImport.remoteFileCount)).localized) }
                        LabeledContent(Messages.AppImportInstanceView.javaText4.localized, value: Messages.AppImportInstanceView.javaText5(Int64(prepared.fileCount), String(describing: LocalizedFormat.bytes(prepared.byteCount))).localized)
                    }.padding(16).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    if !prepared.optionalFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(Messages.AppImportInstanceView.javaText6.localized).font(.headline)
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
                                            Toggle(Messages.AppImportInstanceView.optionalText1(String(describing: item.project.name)).localized, isOn: Binding(get: { !excluded.contains(item.id) }, set: { if $0 { excluded.remove(item.id) } else { excluded.insert(item.id) } }))
                                        }
                                        if !excluded.contains(item.id) {
                                            CurseForgeFileRow(file: item.file, title: item.project.name, page: item.pageURL, manual: item.requiresManualDownload, selectedURL: Binding(get: { manualFiles[item.id] }, set: { manualFiles[item.id] = $0 }))
                                        }
                                    }
                                }
                            }.frame(maxHeight: 230)
                        } else if resolving { ProgressView(Messages.AppImportInstanceView.optionalText2.localized) }
                        else {
                            Text(Messages.AppImportInstanceView.optionalText3.localized).foregroundStyle(.secondary)
                            if model.curseForgeConfigured { Button(Messages.AppImportInstanceView.optionalText4.localized) { resolve() } }
                            else { Text(Messages.AppImportInstanceView.optionalText5.localized).font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.orange) }
                    if !prepared.warnings.isEmpty && files == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(prepared.warnings, id: \.self) { warning in Label(warning, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                    if let arguments = prepared.instance.extraGameArguments, !arguments.isEmpty { Text(Messages.AppImportInstanceView.gameArguments(arguments).localized).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    if !prepared.instance.extraJVMArguments.isEmpty {
                        Toggle(Messages.AppImportInstanceView.argumentsText2.localized, isOn: $keepJVMArguments)
                        ScrollView { Text(prepared.instance.extraJVMArguments).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 75)
                    }
                }
            }
            HStack {
                Button(Messages.Common.cancel.localized) { task?.cancel(); if let onCancel { onCancel() } else { model.cancelImport(prepared) } }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Spacer()
                Button(updateTarget == nil ? Messages.AppImportInstanceView.onCancelText1.localized : Messages.AppImportInstanceView.onCancelText2.localized) {
                    if let updateTarget, let onPreparedUpdate {
                        model.prepareModpackUpdate(selectedImport, instance: updateTarget, keepJVMArguments: keepJVMArguments, curseFiles: chosenFiles, manualFiles: manualFiles, completion: onPreparedUpdate)
                    } else { model.finishImport(selectedImport, name: name, keepJVMArguments: keepJVMArguments, curseFiles: chosenFiles, manualFiles: manualFiles) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || resolving || !ready || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
