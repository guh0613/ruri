import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CurseForgeInstallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: CurseForgeProject
    @State private var versions: [CurseForgeFile] = []
    @State private var selectedID: Int?
    @State private var instanceID: UUID?
    @State private var offset = 0
    @State private var total = 0
    @State private var loading = false
    @State private var resolving = false
    @State private var error: String?
    @State private var plan: CurseForgeContentPlan?
    @State private var manualFiles: [Int: URL] = [:]
    @State private var resolution: Task<Void, Never>?
    private var instance: GameInstance? { model.state.instances.first { $0.id == instanceID } }
    private var isPack: Bool { project.contentType == "modpack" }
    private var selected: CurseForgeFile? { versions.first { $0.id == selectedID } }
    private var packIsManual: Bool { project.allowModDistribution == false || selected?.downloadURL == nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: project.name, subtitle: "CurseForge · \(project.authors?.map(\.name).joined(separator: ", ") ?? Messages.AppCurseForgeInstallView.communityContent.localized)")
            if let plan {
                Text(Messages.AppCurseForgeInstallView.installPlan(plan.instance.name, Int64(plan.files.count)).localized).foregroundStyle(.secondary)
                ScrollView { CurseForgePlanFiles(files: plan.files, manualFiles: $manualFiles) }.frame(maxHeight: 360)
            } else {
                Text(project.summary).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                if !isPack {
                    Picker(Messages.AppCurseForgeInstallView.installToInstance.localized, selection: $instanceID) {
                        Text(Messages.AppCurseForgeInstallView.chooseInstance.localized).tag(nil as UUID?)
                        ForEach(model.state.instances.filter { $0.installed && (project.contentType != "mod" || $0.loader != .vanilla) }) { Text($0.name + " · " + $0.subtitle).tag(Optional($0.id)) }
                    }.disabled(resolving)
                }
                if loading { ProgressView(Messages.AppCurseForgeInstallView.findCompatibleVersions.localized) }
                else if !versions.isEmpty {
                    Picker(Messages.AppCurseForgeInstallView.contentVersion.localized, selection: $selectedID) { ForEach(versions) { Text($0.displayName + ($0.releaseType == 2 ? " · Beta" : $0.releaseType == 3 ? " · Alpha" : "")).tag(Optional($0.id)) } }.disabled(resolving)
                } else { Text(isPack || instance != nil ? Messages.AppCurseForgeInstallView.noCompatibleVersions.localized : Messages.AppCurseForgeInstallView.instanceSelectionNotice.localized).foregroundStyle(.secondary) }
                if total > 50 {
                    HStack { Button(Messages.AppCurseForgeInstallView.previousPage.localized) { offset = max(0, offset - 50) }.disabled(offset == 0 || loading || resolving); Text(Messages.AppCurseForgeInstallView.pageNumber(Int64(offset / 50 + 1)).localized).font(.caption); Button(Messages.AppCurseForgeInstallView.nextPage.localized) { offset += 50 }.disabled(offset + 50 >= total || loading || resolving) }
                }
                if isPack, let file = selected, packIsManual {
                    CurseForgeFileRow(file: file, title: Messages.AppCurseForgeInstallView.packManifest.localized, page: project.page(for: file.id), manual: true, selectedURL: Binding(get: { manualFiles[file.id] }, set: { manualFiles[file.id] = $0 }))
                }
                if project.contentType == "shader" { Text(Messages.AppCurseForgeInstallView.shaderpackNotice.localized).font(.caption).foregroundStyle(.secondary) }
            }
            if resolving { ProgressView(Messages.AppCurseForgeInstallView.resolveDependencies.localized) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange) }
            HStack {
                if plan != nil { Button(Messages.AppCurseForgeInstallView.back.localized) { plan = nil } }
                Spacer(); Button(Messages.Common.cancel.localized) { resolution?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(plan == nil ? (isPack ? Messages.AppCurseForgeInstallView.readPack.localized : Messages.AppCurseForgeInstallView.viewInstallPlan.localized) : Messages.AppCurseForgeInstallView.install.localized) { advance() }.buttonStyle(.borderedProminent).disabled(!canContinue)
            }
        }.padding(26).frame(width: 570).interactiveDismissDisabled(resolving)
        .onAppear { instanceID = model.selected.flatMap { project.contentType == "mod" && $0.loader == .vanilla ? nil : $0.id } }
        .onChange(of: instanceID) { offset = 0 }
        .onDisappear { resolution?.cancel() }
        .task(id: "\(instanceID?.uuidString ?? "pack"):\(offset)") {
            versions = []; selectedID = nil; total = 0; error = nil
            guard isPack || instance != nil else { return }
            loading = true
            do {
                let page = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).files(project: project.id, game: isPack ? nil : instance?.gameVersion, loader: project.contentType == "mod" ? instance?.loader : nil, offset: offset)
                try Task.checkCancellation()
                versions = page.data.filter { file in
                    guard file.modId == project.id, file.isAvailable != false else { return false }
                    if isPack { return true }
                    guard let instance, let kind = project.contentType.flatMap(ContentKind.init(rawValue:)) else { return false }
                    return file.supports(instance, kind: kind)
                }
                total = page.pagination?.totalCount ?? page.data.count; selectedID = versions.first?.id; loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
    private var canContinue: Bool {
        guard !loading, !resolving, !model.busy else { return false }
        if let plan { return !model.isInstanceInUse(plan.instance.id) && plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil } }
        guard let selected else { return false }
        return isPack ? (!packIsManual || manualFiles[selected.id] != nil) : instance != nil && !model.isInstanceInUse(instanceID)
    }
    private func advance() {
        if let plan { model.installCurseForge(plan, manualFiles: manualFiles); dismiss(); return }
        guard let file = selected else { return }
        if isPack { model.readCurseForgePack(project, file: file, manual: manualFiles[file.id]); dismiss(); return }
        guard let instance else { return }
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

struct CurseForgePlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: CurseForgeContentPlan
    @State private var manualFiles: [Int: URL] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: Messages.AppCurseForgeInstallView.updatePack(plan.title).localized, subtitle: Messages.AppCurseForgeInstallView.updateSummary(plan.instance.name, Int64(plan.files.count)).localized)
            ScrollView { CurseForgePlanFiles(files: plan.files, manualFiles: $manualFiles) }.frame(maxHeight: 360)
            HStack { Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(Messages.AppCurseForgeInstallView.update.localized) { model.installCurseForge(plan, manualFiles: manualFiles); dismiss() }.buttonStyle(.borderedProminent).disabled(model.busy || model.isInstanceInUse(plan.instance.id) || !plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil }) }
        }.padding(26).frame(width: 570)
    }
}
