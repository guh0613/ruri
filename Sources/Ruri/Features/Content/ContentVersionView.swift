import RuriLocalization
import SwiftUI
import RuriCore

struct ContentVersionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let record: ManagedContent
    let instanceID: UUID
    @State private var versions: [Choice] = []
    @State private var selectedID: String?
    @State private var includePrereleases = false
    @State private var loading = false
    @State private var resolving = false
    @State private var error: String?
    @State private var offset = 0
    @State private var total = 0
    @State private var plan: CurseForgeContentPlan?
    @State private var manualFiles: [Int: URL] = [:]
    @State private var resolution: Task<Void, Never>?
    private var instance: GameInstance? { model.state.instances.first { $0.id == instanceID } }
    private var choices: [Choice] { versions.filter { includePrereleases || $0.isRelease || $0.id == record.versionID } }
    private var selected: Choice? { choices.first { $0.id == selectedID } }
    private var requestKey: String { "\(instance?.gameVersion ?? ""): \(instance?.loader.modrinthLoader ?? ""): \(offset)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: Messages.AppContentVersionView.replaceVersion.localized, subtitle: record.title)
            Text(Messages.AppContentVersionView.currentVersion(record.versionName, String(describing: instance?.name ?? Messages.AppContentVersionView.instanceRemoved.localized)).localized)
                .font(.callout).foregroundStyle(.secondary)
            if let plan {
                Text(Messages.AppContentVersionView.installPlan(Int64(plan.files.count)).localized).font(.callout)
                ScrollView { CurseForgePlanFiles(files: plan.files, manualFiles: $manualFiles) }.frame(height: 260)
            } else {
                Toggle(Messages.AppContentVersionView.includePrereleases.localized, isOn: $includePrereleases).disabled(resolving)
                if loading { ProgressView(Messages.AppContentVersionView.findCompatibleVersion.localized).frame(maxWidth: .infinity, minHeight: 180) }
                else {
                    List(selection: $selectedID) {
                        ForEach(choices) { choice in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.title).lineLimit(2)
                                    Text(LocalizedFormat.publishedDate(choice.date)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if choice.id == record.versionID { TagPill(text: Messages.AppContentVersionView.installed.localized) }
                                TagPill(text: choice.channel)
                            }.padding(.vertical, 4).tag(choice.id)
                        }
                    }.frame(height: 230).disabled(resolving)
                    if choices.isEmpty { Text(Messages.AppContentVersionView.noMatchingVersion.localized).font(.caption).foregroundStyle(.secondary) }
                }
                if record.provider == "curseforge", total > 50 {
                    HStack {
                        Button(Messages.AppContentVersionView.previousPage.localized) { offset = max(0, offset - 50) }.disabled(offset == 0 || loading || resolving)
                        Text(Messages.AppContentVersionView.pageNumber(Int64(offset / 50 + 1)).localized).font(.caption)
                        Button(Messages.AppContentVersionView.nextPage.localized) { offset += 50 }.disabled(offset + 50 >= total || loading || resolving)
                    }
                }
                Text(Messages.AppContentVersionView.versionSelectionInfo.localized).font(.caption).foregroundStyle(.secondary)
            }
            if resolving { ProgressView(Messages.AppContentVersionView.resolveDependencies.localized) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                if plan != nil { Button(Messages.AppContentVersionView.returnToVersions.localized) { plan = nil; manualFiles = [:] } }
                Spacer()
                Button(Messages.Common.cancel.localized) { resolution?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(plan != nil || record.provider == "modrinth" ? Messages.AppContentVersionView.installSelectedVersion.localized : Messages.AppContentVersionView.viewInstallPlan.localized, action: install)
                    .buttonStyle(.borderedProminent).disabled(!canInstall)
            }
        }.padding(24).frame(width: 600)
        .task(id: requestKey) { await loadVersions() }
        .onDisappear { resolution?.cancel() }
        .interactiveDismissDisabled(resolving)
    }

    private var canInstall: Bool {
        guard instance != nil, !loading, !resolving, !model.busy, !model.isInstanceInUse(instanceID) else { return false }
        if let plan { return plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil } }
        return selected != nil && selectedID != record.versionID
    }

    private func loadVersions() async {
        resolution?.cancel(); resolving = false; loading = false
        versions = []; selectedID = nil; error = nil; plan = nil; manualFiles = [:]; total = 0
        guard let instance else { return }
        loading = true
        do {
            if record.provider == "modrinth" {
                let result = try await ModrinthService().versions(project: record.projectID, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader.modrinthLoader : nil)
                try Task.checkCancellation()
                versions = result.filter {
                    $0.project_id == record.projectID && $0.game_versions.contains(instance.gameVersion) &&
                    (record.kind != .mod || $0.loaders.contains(instance.loader.modrinthLoader)) && $0.primaryFile != nil
                }.map(Choice.modrinth)
            } else if record.provider == "curseforge", let project = Int(record.projectID) {
                let page = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).files(project: project, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader : nil, offset: offset)
                try Task.checkCancellation()
                versions = page.data.filter { $0.modId == project && $0.isAvailable != false && $0.supports(instance, kind: record.kind) }.map(Choice.curseforge)
                total = page.pagination?.totalCount ?? page.data.count
            } else { throw RuriError.message(Messages.AppContentVersionView.noVersionSource) }
            var seen = Set<String>(); versions = versions.filter { seen.insert($0.id).inserted }
            if versions.contains(where: { $0.id == record.versionID }) { selectedID = record.versionID }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        if !Task.isCancelled { loading = false }
    }

    private func install() {
        guard canInstall, let instance else { return }
        if let plan { model.installCurseForge(plan, manualFiles: manualFiles); dismiss(); return }
        guard let selected else { return }
        switch selected {
        case .modrinth(let version):
            model.perform(Messages.AppContentVersionView.replaceItemVersion(record.title), instanceID: instanceID) { id in
                try await ModrinthService().install(version: version, type: record.kind.rawValue, instance: instance, paths: model.paths, downloader: model.installer.downloader) { progress in await model.progress(id, progress) }
                model.notice = Messages.AppContentVersionView.versionReplaced(record.title, String(describing: version.version_number)).localized
            }
            dismiss()
        case .curseforge(let file):
            resolving = true; error = nil
            resolution = Task {
                do {
                    let result = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).plan(file: file, instance: instance, paths: model.paths)
                    try Task.checkCancellation(); plan = result
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                resolving = false
            }
        }
    }

    private enum Choice: Identifiable {
        case modrinth(ModrinthVersion), curseforge(CurseForgeFile)
        var id: String { switch self { case .modrinth(let value): value.id; case .curseforge(let value): String(value.id) } }
        var title: String { switch self { case .modrinth(let value): value.name; case .curseforge(let value): value.displayName } }
        var date: String { switch self { case .modrinth(let value): value.date_published ?? ""; case .curseforge(let value): value.fileDate } }
        var channel: String {
            switch self {
            case .modrinth(let value): value.version_type == "beta" ? "Beta" : value.version_type == "alpha" ? "Alpha" : Messages.AppContentVersionView.stableRelease.localized
            case .curseforge(let value): value.releaseType == 2 ? "Beta" : value.releaseType == 3 ? "Alpha" : Messages.AppContentVersionView.stableRelease.localized
            }
        }
        var isRelease: Bool {
            switch self {
            case .modrinth(let value): value.version_type != "beta" && value.version_type != "alpha"
            case .curseforge(let value): value.releaseType != 2 && value.releaseType != 3
            }
        }
    }
}
