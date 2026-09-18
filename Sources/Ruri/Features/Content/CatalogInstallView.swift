import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery
private enum CatalogDestination: String, CaseIterable { case instance, newInstance, file }

struct CatalogInstallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: CatalogProject
    let version: CatalogVersion
    @State private var destination = CatalogDestination.instance
    @State private var instanceID: UUID?
    @State private var name = ""
    @State private var game = ""
    @State private var loader = LoaderKind.vanilla
    @State private var loaderVersion = ""
    @State private var loaderVersions: [String] = []
    @State private var loadingLoader = false
    @State private var loaderError: String?
    @State private var plan: CatalogInstallPlan?
    @State private var resolvedKey = ""
    @State private var resolving = false
    @State private var error: String?
    @State private var retry = 0
    @State private var manualFiles: [Int: URL] = [:]
    @State private var showAllInstances = false
    private var isPack: Bool { project.type == "modpack" }
    private var instances: [GameInstance] { model.state.instances.filter(\.installed) }
    private var compatible: [GameInstance] { instances.filter { version.supports($0, type: project.type) } }
    private var selected: GameInstance? { instances.first { $0.id == instanceID } }
    private var availableLoaders: [LoaderKind] { project.type == "mod" ? LoaderKind.allCases.filter { $0 != .vanilla && version.loaders.contains($0.modrinthLoader) } : [.vanilla] }
    private var loaderKey: String { "\(destination.rawValue)|\(game)|\(loader.rawValue)" }
    private var planKey: String { "\(loaderKey)|\(loaderVersion)|\(instanceID?.uuidString ?? "")|\(selected?.gameVersion ?? "")|\(selected?.loader.rawValue ?? "")|\(selected?.loaderVersion ?? "")|\(model.selectedDirectoryID)|\(retry)" }
    private var manualRoot: CurseForgeFile? {
        guard case .curseforge = project, case .curseforge(let f) = version, f.downloadURL == nil else { return nil }
        return f
    }
    private var ready: Bool {
        guard !model.busy, !model.readOnly else { return false }
        if destination == .file || isPack { return manualRoot.map { manualFiles[$0.id] != nil } ?? true }
        guard let plan, resolvedKey == planKey, !resolving else { return false }
        if destination == .instance && model.isInstanceInUse(plan.instance.id) { return false }
        return plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                CatalogIcon(url: project.icon, size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.title).font(.title2.weight(.semibold))
                    Text(version.name).font(.callout).foregroundStyle(.secondary)
                    WrappingLayout(spacing: 6) {
                        CatalogGameVersionsBadge(versions: version.gameVersions)
                        if !version.loaders.isEmpty { CatalogLoaderBadges(loaders: version.loaders) }
                    }
                }
                Spacer()
            }.padding(24)
            Picker(D.destination.localized, selection: $destination) {
                if !isPack { Text(D.existingInstance.localized).tag(CatalogDestination.instance) }
                Text(D.newInstance.localized).tag(CatalogDestination.newInstance)
                Text(D.saveFile.localized).tag(CatalogDestination.file)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if destination == .file {
                        Label(D.saveFileNotice.localized, systemImage: "folder").foregroundStyle(.secondary)
                        fileSummary
                        if !version.dependencies.isEmpty { Text(D.fileDependenciesNotice.localized).font(.callout).foregroundStyle(.secondary) }
                        manualRootView
                    } else if isPack {
                        Label(D.modpackImportNotice.localized, systemImage: "shippingbox").foregroundStyle(.secondary)
                        fileSummary
                        manualRootView
                    } else {
                        if destination == .instance { instanceSelection }
                        else { newInstanceFields }
                        Divider()
                        if project.type == "shader" { Label(Messages.AppContentInstallView.shaderHelp.localized, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                        if resolving { ProgressView(D.checkingDependencies.localized).frame(maxWidth: .infinity).padding(.vertical, 22) }
                        else if let plan, resolvedKey == planKey { preview(plan) }
                        if let error { CatalogErrorBanner(message: error) { retry += 1 } }
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                if let plan, destination != .file, !isPack, resolvedKey == planKey {
                    Text(D.installSummary(Int64(plan.pending.count), LocalizedFormat.bytes(plan.downloadSize)).localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(actionTitle) { advance() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!ready)
            }.padding(20)
        }.frame(width: 660, height: 670)
        .onAppear {
            instanceID = compatible.first { $0.id == model.discovery.preferredInstanceID }?.id ?? compatible.first { $0.id == model.selected?.id }?.id ?? compatible.first?.id
            game = CatalogMetadata.sortedVersions(version.gameVersions).first { candidate in model.catalog?.versions.contains { $0.id == candidate && $0.isRelease } == true } ?? CatalogMetadata.sortedVersions(version.gameVersions).first ?? ""
            loader = availableLoaders.first ?? .vanilla
            if isPack || compatible.isEmpty { destination = .newInstance }
            if !isPack && availableLoaders.isEmpty { destination = compatible.isEmpty ? .file : .instance }
        }
        .task(id: loaderKey) {
            loadingLoader = false
            guard destination == .newInstance, !isPack else { return }
            loaderVersions = []; loaderVersion = ""; loaderError = nil
            guard loader != .vanilla, !game.isEmpty else { return }
            loadingLoader = true
            defer { if !Task.isCancelled { loadingLoader = false } }
            do {
                let options = try await model.installer.loaderVersions(loader, game: game)
                try Task.checkCancellation(); loaderVersions = options; loaderVersion = options.first ?? ""
                if options.isEmpty { loaderError = Messages.AppCreateInstanceView.noCompatibleLoader.localized }
            } catch { if !Task.isCancelled { loaderError = error.localizedDescription } }
        }
        .task(id: planKey) { await prepare() }
    }
    private var actionTitle: String {
        if destination == .file { return D.chooseSaveLocation.localized }
        if isPack { return D.readModpack.localized }
        if destination == .newInstance { return D.createAndInstall.localized }
        if plan?.pending.isEmpty == true { return D.done.localized }
        return D.confirmInstall.localized
    }
    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(version.filename).font(.headline).textSelection(.enabled)
            Text(LocalizedFormat.bytes(version.size)).font(.callout).foregroundStyle(.secondary)
            Label(D.verifiedDownload.localized, systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private var manualRootView: some View {
        if let file = manualRoot, case .curseforge(let p) = project {
            Text(Messages.AppCurseForgeFilePicker.manualDownloadNotice.localized).font(.callout).foregroundStyle(.secondary)
            CurseForgeFileRow(file: file, title: project.title, page: p.page(for: file.id), manual: true, selectedURL: Binding(get: { manualFiles[file.id] }, set: { manualFiles[file.id] = $0 }))
        }
    }
    private var instanceSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(D.chooseInstance.localized).font(.headline)
                Spacer()
                Toggle(D.showIncompatible.localized, isOn: $showAllInstances).toggleStyle(.checkbox).font(.caption)
            }
            if compatible.isEmpty { Text(D.noCompatibleInstance.localized).font(.callout).foregroundStyle(.secondary) }
            ForEach(showAllInstances ? instances : compatible) { instance in
                let supports = version.supports(instance, type: project.type)
                let inUse = model.isInstanceInUse(instance.id)
                Button { instanceID = instance.id } label: {
                    HStack(spacing: 12) {
                        InstanceIcon(instance, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(instance.name).font(.headline)
                            Text(instance.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if inUse { Text(D.instanceInUse.localized).font(.caption).foregroundStyle(.orange) }
                        else if !supports { Text(D.incompatibleTarget.localized).font(.caption).foregroundStyle(.secondary) }
                        else { Image(systemName: instanceID == instance.id ? "checkmark.circle.fill" : "circle").foregroundStyle(instanceID == instance.id ? Theme.accent : .secondary) }
                    }.padding(12).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!supports || inUse)
                    .background(instanceID == instance.id ? Theme.accent.opacity(0.08) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private var newInstanceFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(D.createCompatibleInstance.localized).font(.headline)
            TextField(Messages.AppCreateInstanceView.instanceNameOptional.localized, text: $name).textFieldStyle(.roundedBorder)
            Label(Messages.AppCreateInstanceView.saveLocation(model.selectedDirectoryName).localized, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker(D.gameVersion.localized, selection: $game) { ForEach(CatalogMetadata.sortedVersions(version.gameVersions), id: \.self) { Text($0).tag($0) } }
                Picker(D.loader.localized, selection: $loader) { ForEach(availableLoaders) { Text($0.title).tag($0) } }
            }
            if loader != .vanilla {
                if loadingLoader { ProgressView(Messages.AppCreateInstanceView.findCompatibleLoaders.localized).controlSize(.small) }
                else if let loaderError { Text(loaderError).font(.caption).foregroundStyle(.orange) }
                else { Picker(Messages.AppCreateInstanceView.loaderVersion.localized, selection: $loaderVersion) { ForEach(loaderVersions, id: \.self) { Text($0).tag($0) } } }
            }
            Text(D.newInstanceNotice.localized).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func preview(_ plan: CatalogInstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(D.installPreview.localized, systemImage: "checkmark.shield").font(.headline)
            Text(D.dependencyPreviewNotice.localized).font(.callout).foregroundStyle(.secondary)
            ForEach(plan.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.action == .keep ? "checkmark.circle.fill" : item.isRoot ? "shippingbox" : "link").foregroundStyle(item.action == .keep ? .green : Theme.accent).frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.record.title).font(.callout.weight(.medium))
                            if !item.isRoot {
                                Button { openDependency(item) } label: {
                                    Label(D.viewProject.localized, systemImage: "arrow.up.forward.square")
                                }
                                .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                                .foregroundStyle(.secondary).help(D.viewProject.localized)
                            }
                        }
                        Text(item.record.versionName).font(.caption).foregroundStyle(.secondary)
                        if let previous = item.previousVersion, (item.action == .update || item.action == .updateAndEnable) { Text(D.replacingVersion(previous).localized).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(item.action.title).font(.caption).foregroundStyle(item.action == .keep ? .secondary : Theme.accent)
                        .fixedSize(horizontal: true, vertical: false)
                }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            if plan.untrackedFiles > 0 { Text(D.untrackedNotice(Int64(plan.untrackedFiles)).localized).font(.caption).foregroundStyle(.secondary) }
            if !plan.manualFiles.isEmpty {
                Text(Messages.AppCurseForgeFilePicker.manualDownloadNotice.localized).font(.callout).foregroundStyle(.secondary)
                CurseForgePlanFiles(files: plan.manualFiles, manualFiles: $manualFiles)
            }
        }
    }
    private func prepare() async {
        let key = planKey
        plan = nil; resolvedKey = ""; error = nil; resolving = false
        guard !isPack, destination != .file else { return }
        let instance: GameInstance
        if destination == .instance {
            guard let selected, version.supports(selected, type: project.type), !model.isInstanceInUse(selected.id) else { return }
            instance = selected
        } else {
            guard !game.isEmpty, availableLoaders.contains(loader), loader == .vanilla || !loaderVersion.isEmpty else { return }
            var draft = GameInstance(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? project.title : name, gameVersion: game, loader: loader, loaderVersion: loader == .vanilla ? nil : loaderVersion)
            draft.launchOverrides = .init()
            draft.directoryID = model.paths.newInstanceDirectoryID
            draft.runDirectory = (model.state.settings.isolationPolicy ?? .always).directory(loader: loader)
            instance = draft
        }
        resolving = true
        defer { if key == planKey { resolving = false } }
        do {
            try await Task.sleep(for: .milliseconds(200))
            let result = try await CatalogInstallationPlanner().plan(project: project, version: version, instance: instance, paths: model.paths, newInstance: destination == .newInstance)
            try Task.checkCancellation(); guard key == planKey else { return }
            plan = result; resolvedKey = key
        } catch { if !Task.isCancelled, key == planKey { self.error = error.localizedDescription } }
    }
    private func openDependency(_ item: CatalogPlannedItem) {
        Task {
            do {
                let p = try await model.catalogRepository.project(source: project.source, id: item.record.projectID)
                dismiss(); model.discovery.open(p)
            } catch { self.error = error.localizedDescription }
        }
    }
    private func advance() {
        guard ready else { return }
        if destination == .file {
            if model.saveCatalogFile(project: project, version: version, manualFiles: manualFiles) { dismiss() }
        } else if isPack {
            dismiss()
            switch (project, version) {
            case (.modrinth(let p), .modrinth(let v)): model.installContent(project: p, version: v, instance: nil)
            case (.curseforge(let p), .curseforge(let f)): model.readCurseForgePack(p, file: f, manual: manualFiles[f.id])
            default: break
            }
        } else if let plan {
            if !plan.pending.isEmpty || destination == .newInstance { model.installCatalog(plan, newInstance: destination == .newInstance, name: name, manualFiles: manualFiles) }
            dismiss()
        }
    }
}
