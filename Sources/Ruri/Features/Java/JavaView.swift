import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// Local Java installations and the official runtimes available for
/// download, as a grouped settings-style list.
struct JavaView: View {
    @Environment(AppModel.self) private var model
    @State private var available: [RemoteJava] = []
    @State private var javaError: String?
    @State private var loadingRemote = false
    @State private var removal: JavaRemovalRequest?
    var body: some View {
        Form {
            Section {
                if model.scanningJava { ProgressView(Messages.AppJavaView.bodyText1.localized).controlSize(.small) }
                if model.javaEntries.isEmpty && !model.scanningJava {
                    Label(Messages.AppJavaView.bodyText2.localized, systemImage: "cup.and.saucer").foregroundStyle(.secondary).padding(.vertical, 4)
                }
                ForEach(model.javaEntries) { entry in runtimeRow(entry) }
            } header: {
                Text(Messages.AppJavaView.bodyText3.localized)
            }
            Section {
                if loadingRemote { ProgressView(Messages.AppJavaView.bodyText4.localized).controlSize(.small) }
                if let javaError { Text(javaError).font(.caption).foregroundStyle(.orange) }
                ForEach(available) { runtime in remoteRow(runtime) }
            } header: {
                Text(Messages.AppJavaView.javaErrorText1.localized)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Messages.AppJavaView.javaErrorText2.localized)
                    HStack(spacing: 14) { Link(Messages.AppJavaView.javaErrorText3.localized, destination: AppLinks.azulJavaDownloads); Link(Messages.AppJavaView.javaErrorText4.localized, destination: AppLinks.temurinJavaDownloads) }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await model.scanJava() } } label: { Label(Messages.AppJavaView.javaErrorText5.localized, systemImage: "arrow.clockwise") }.help(Messages.AppJavaView.javaErrorText6.localized).disabled(model.scanningJava || model.busy)
                Button { model.chooseJava() } label: { Label(Messages.AppJavaView.javaErrorText7.localized, systemImage: "plus") }.help(Messages.AppJavaView.javaErrorText8.localized).disabled(model.busy)
            }
        }
        .sheet(item: $removal) { JavaRemovalView(request: $0) }
        .task {
            loadingRemote = true
            do { available = try await JavaInstaller(paths: model.paths).available() } catch { javaError = error.localizedDescription }
            loadingRemote = false
        }
    }
    private func runtimeRow(_ entry: JavaRuntimeEntry) -> some View {
        let remote = entry.remote ?? available.first { $0.id == entry.managedID }
        let runtime = entry.runtime ?? entry.addedRuntime
        return HStack(spacing: 12) {
            Text(runtime.map { String($0.major) } ?? remote.map { String($0.major) } ?? "?")
                .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(entry.issue == nil ? Theme.accent : .orange)
                .frame(width: 40, height: 40).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(runtime?.label ?? remote?.label ?? Messages.AppJavaView.runtimeText1.localized).font(.headline)
                    TagPill(text: entry.source)
                    if let selected = model.state.settings.defaultLaunchSettings.java.path, JavaDiscovery.sameExecutable(selected, entry.path) { TagPill(text: Messages.AppJavaView.selectedText1.localized) }
                }
                if let issue = entry.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                else if let runtime { Text(runtime.version).font(.caption).foregroundStyle(.secondary) }
                Text(entry.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(entry.path)
            }
            Spacer()
            if let remote { Button(Messages.AppJavaView.remoteText1.localized) { model.installJava(remote, repairing: true) }.disabled(model.busy) }
            Menu {
                if entry.runtime != nil { Button(Messages.AppJavaView.remoteText2.localized, systemImage: "checkmark.circle") { model.defaultJava(entry.path) } }
                Button(Messages.AppJavaView.remoteText3.localized, systemImage: "folder") { model.chooseJava(replacing: entry.path) }
                Button(Messages.AppJavaView.remoteText4.localized, systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                if entry.manual { Button(Messages.AppJavaView.remoteText5.localized, systemImage: "minus.circle") { model.forgetJava(entry.path) } }
                if let id = entry.managedID {
                    Divider(); Button(Messages.AppJavaView.idText1.localized, systemImage: "trash", role: .destructive) { requestRemoval(id) }
                }
            } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.busy)
        }
        .padding(.vertical, 4)
    }
    private func remoteRow(_ runtime: RemoteJava) -> some View {
        let installed = model.javaEntries.contains { $0.managedID == runtime.id && $0.runtime != nil }
        let resumable = FileManager.default.fileExists(atPath: model.paths.runtimes.appendingPathComponent(".partial-\(runtime.id)").path)
        let broken = !installed && FileManager.default.fileExists(atPath: model.paths.runtimes.appendingPathComponent(runtime.id).path)
        return HStack {
            Text(runtime.label)
            Spacer()
            if resumable { Button(Messages.AppJavaView.brokenText1.localized) { requestRemoval(runtime.id, partial: true) }.disabled(model.busy) }
            if installed { Text(Messages.AppJavaView.brokenText2.localized).font(.callout).foregroundStyle(.secondary) }
            else { Button(broken ? Messages.AppJavaView.remoteText1.localized : resumable ? Messages.AppJavaView.brokenText3.localized : Messages.AppJavaView.brokenText4.localized) { model.installJava(runtime, repairing: broken) }.disabled(model.busy) }
        }
        .padding(.vertical, 2)
    }
    private func requestRemoval(_ id: String, partial: Bool = false) {
        let entry = model.javaEntries.first { $0.managedID == id }
        let title = entry?.runtime.map { $0.label + " · " + $0.version } ?? entry?.remote?.label ?? available.first { $0.id == id }?.label ?? id
        do { removal = .init(id: id, title: title, partial: partial, references: try JavaRuntimeStore.references(to: id, paths: model.paths, partial: partial)) }
        catch { javaError = error.localizedDescription }
    }
}

private struct JavaRemovalRequest: Identifiable { let id: String; let title: String; let partial: Bool; let references: [String] }
private struct JavaRemovalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: JavaRemovalRequest
    @State private var resetReferences = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.partial ? Messages.AppJavaView.bodyText5.localized : Messages.AppJavaView.bodyText6.localized).font(.title2.bold())
            Text(request.title).font(.callout).textSelection(.enabled)
            if !request.references.isEmpty {
                Text(Messages.AppJavaView.bodyText7.localized).font(.callout)
                ScrollView { VStack(alignment: .leading) { ForEach(Array(request.references.enumerated()), id: \.offset) { _, name in Text(name) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140)
                Toggle(Messages.AppJavaView.bodyText8.localized, isOn: $resetReferences)
            }
            Text(Messages.AppJavaView.bodyText9.localized).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppJavaView.bodyText10.localized, role: .destructive) { model.removeJava(request.id, resetReferences: resetReferences, partial: request.partial); dismiss() }
                    .disabled(!request.references.isEmpty && !resetReferences)
            }
        }.padding(24).frame(width: 480)
    }
}
