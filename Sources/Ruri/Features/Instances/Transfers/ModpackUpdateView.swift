import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ModpackUpdateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var pack: InstalledModpack?
    @State private var releases: [ModpackRelease] = []
    @State private var nextOffset: Int?
    @State private var loading = false
    @State private var includePrereleases = false
    @State private var error: String?
    @State private var prepared: PreparedInstanceImport?
    @State private var plan: PreparedModpackUpdate?
    @State private var keeping = Set<String>()
    private var current: GameInstance { model.state.instances.first { $0.id == instance.id } ?? instance }
    private var pending: Bool { ModpackUpdateStore.hasPending(paths: model.paths, instanceID: instance.id) }
    private var backup: Bool { ModpackUpdateStore.hasBackup(paths: model.paths, instanceID: instance.id) }
    private var displayed: [ModpackRelease] { releases.filter { includePrereleases || $0.stable } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: Messages.AppModpackUpdateView.bodyText1.localized, subtitle: current.name)
            if let pack { Text("\(pack.name) · \(pack.version) · \(pack.format)").font(.callout).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if model.busy { ProgressView(Messages.AppModpackUpdateView.errorText1.localized).controlSize(.small) }
            if pending {
                Text(Messages.AppModpackUpdateView.errorText2.localized)
                Button(Messages.AppModpackUpdateView.errorText3.localized) { model.recoverModpackUpdate(current) { reload() } }.disabled(model.busy)
            } else if let plan {
                preview(plan)
            } else if pack != nil {
                HStack {
                    Button(Messages.AppModpackUpdateView.planText1.localized, systemImage: "doc.badge.arrow.up") { chooseFile() }.disabled(model.busy)
                    Spacer()
                    Toggle(Messages.AppModpackUpdateView.planText2.localized, isOn: $includePrereleases).toggleStyle(.checkbox)
                    Button(Messages.AppModpackUpdateView.planText3.localized) { Task { await loadVersions() } }.disabled(model.busy || loading)
                }
                if loading { ProgressView(Messages.AppModpackUpdateView.planText4.localized).controlSize(.small) }
                if displayed.isEmpty && !loading {
                    ContentUnavailableView(Messages.AppModpackUpdateView.planText5.localized, systemImage: "shippingbox", description: Text(Messages.AppModpackUpdateView.planText6.localized))
                } else {
                    List(displayed) { release in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(release.title).font(.headline)
                                Text(LocalizedFormat.list(release.gameVersions)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if let date = release.publishedAt { Text(LocalizedFormat.publishedDate(date)).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if release.id == pack?.origin?.versionID { Text(Messages.AppModpackUpdateView.dateText1.localized).font(.caption).foregroundStyle(.secondary) }
                            else {
                                if let page = release.page, release.requiresManualDownload { Link(Messages.AppModpackUpdateView.pageText1.localized, destination: page) }
                                Button(release.requiresManualDownload ? Messages.AppModpackUpdateView.pageText2.localized : Messages.AppModpackUpdateView.pageText3.localized) { select(release) }.disabled(model.busy)
                            }
                        }.padding(.vertical, 5)
                    }.listStyle(.bordered)
                }
                if let nextOffset { Button(Messages.AppModpackUpdateView.nextOffsetText1.localized) { Task { await loadVersions(offset: nextOffset) } }.disabled(loading || model.busy) }
                if backup {
                    Divider()
                    Text(Messages.AppModpackUpdateView.nextOffsetText2.localized).font(.caption).foregroundStyle(.secondary)
                    Button(Messages.AppModpackUpdateView.nextOffsetText3.localized, systemImage: "arrow.uturn.backward") { model.rollbackModpack(current) { reload() } }.disabled(model.busy)
                }
            } else {
                Text(Messages.AppModpackUpdateView.nextOffsetText4.localized).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack { Spacer(); Button(Messages.AppModpackUpdateView.nextOffsetText5.localized) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy) }
        }.padding(24).frame(width: 680, height: 650).interactiveDismissDisabled(model.busy)
        .task { reload(); await loadVersions() }
        .sheet(item: $prepared) { value in
            ImportInstanceView(prepared: value, updateTarget: current, onPreparedUpdate: { incoming in
                prepared = nil; plan = incoming; keeping = Set(incoming.changes.filter { $0.action == .keep }.map(\.id))
            }, onCancel: {
                prepared = nil; Task { await InstanceTransfer(paths: model.paths).discard(value) }
            })
        }
        .onDisappear {
            if let plan { Task { await ModpackUpdater(paths: model.paths).discard(plan) } }
        }
    }
    @ViewBuilder private func preview(_ plan: PreparedModpackUpdate) -> some View {
        Text("\(plan.current.version) → \(plan.incoming.version)").font(.headline)
        Text("Minecraft \(plan.instance.gameVersion) → \(plan.incoming.settings.gameVersion) · \(plan.incoming.settings.loader.title) \(plan.incoming.settings.loaderVersion ?? "")").font(.callout)
        Text(Messages.AppModpackUpdateView.previewText1.localized).font(.caption).foregroundStyle(.secondary)
        if plan.instance.gameVersion != plan.incoming.settings.gameVersion {
            Text(Messages.AppModpackUpdateView.previewText2.localized).font(.caption).foregroundStyle(.secondary)
        }
        List(plan.changes) { change in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.id).font(.system(.callout, design: .monospaced)).lineLimit(2)
                    if let explanation = change.explanation { Text(explanation).font(.caption).foregroundStyle(change.conflict ? .orange : .secondary) }
                }
                Spacer()
                if change.conflict {
                    Toggle(Messages.AppModpackUpdateView.explanationText1.localized, isOn: Binding(get: { keeping.contains(change.id) }, set: { if $0 { keeping.insert(change.id) } else { keeping.remove(change.id) } })).toggleStyle(.checkbox)
                } else { Text(change.action.title).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 3)
        }.listStyle(.bordered)
        HStack {
            Button(Messages.AppModpackUpdateView.explanationText2.localized) { Task { await ModpackUpdater(paths: model.paths).discard(plan) }; self.plan = nil }.disabled(model.busy)
            Spacer()
            Text(Messages.AppModpackUpdateView.explanationText3(Int64(plan.changes.filter { !keeping.contains($0.id) }.count)).localized).font(.caption).foregroundStyle(.secondary)
            Button(Messages.AppModpackUpdateView.explanationText4.localized) { model.applyModpackUpdate(plan, keeping: keeping) { self.plan = nil; reload() } }.buttonStyle(.borderedProminent).disabled(model.busy)
        }
    }
    private func reload() {
        do { pack = try ModpackRegistry.load(paths: model.paths, instanceID: instance.id); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func loadVersions(offset: Int = 0) async {
        guard let pack, !pending else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let key = pack.origin?.provider == .curseforge ? try CurseForgeKeyStore.load() : ""
            let result = try await ModpackReleaseService().versions(for: pack, curseForgeKey: key, offset: offset)
            try Task.checkCancellation()
            releases = offset == 0 ? result.items : releases + result.items.filter { incoming in !releases.contains { $0.id == incoming.id } }
            nextOffset = result.nextOffset
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, UTType(filenameExtension: "mrpack") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform(Messages.AppModpackUpdateView.urlText1) { _ in prepared = try await InstanceTransfer(paths: model.paths).prepare(url) }
    }
    private func select(_ release: ModpackRelease) {
        var manual: URL?
        if release.requiresManualDownload {
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.zip]
            guard panel.runModal() == .OK else { return }; manual = panel.url
        }
        let selectedFile = manual
        model.perform(Messages.AppModpackUpdateView.selectedFileText1) { id in
            let downloader = await model.installer.downloader
            prepared = try await ModpackReleaseService().prepare(release, manualFile: selectedFile, paths: model.paths, downloader: downloader) { p in await model.progress(id, p) }
        }
    }
}
