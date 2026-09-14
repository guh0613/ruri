import RuriLocalization
import SwiftUI
import RuriCore

private typealias D = Messages.Discovery

struct CatalogDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    let project: CatalogProject
    @State private var detail: CatalogDetail?
    @State private var error: String?
    @State private var retry = 0
    @State private var tab = "overview"
    @State private var consumedRetry = 0
    private var current: CatalogProject { detail?.project ?? project }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                CatalogProjectTabs(selection: $tab)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
            if let error, detail != nil { CatalogErrorBanner(message: error) { retry += 1 }.padding(.horizontal, 24).padding(.vertical, 10) }
            if tab == "versions" {
                CatalogVersionsView(project: current, refreshToken: retry)
            } else if let detail {
                if tab == "gallery" { gallery(detail) }
                else { overview(detail) }
            } else if let error {
                VStack { CatalogErrorBanner(message: error) { retry += 1 }; Spacer() }.padding(24)
            } else { ProgressView(D.loadingDetail.localized).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.canvas(for: colorScheme))
        .navigationTitle(project.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { retry += 1 } label: { Label(D.refresh.localized, systemImage: "arrow.clockwise") }.labelStyle(.iconOnly).help(D.refresh.localized)
                if let url = current.pageURL {
                    Button { openURL(url) } label: { Label(D.openWebsite.localized, systemImage: "safari") }
                        .labelStyle(.iconOnly).help(D.openProviderWebsite(project.source.rawValue).localized)
                }
            }
        }
        .task(id: retry) {
            if detail != nil && retry == consumedRetry { return }
            let force = retry > consumedRetry; consumedRetry = retry
            error = nil
            do {
                let result = try await model.catalogRepository.detail(project, refresh: force)
                try Task.checkCancellation(); detail = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                CatalogIcon(url: current.icon, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.title).font(.title2.weight(.bold)).textSelection(.enabled)
                    Text(Messages.AppDiscoverView.authorBy(project.author).localized).font(.callout).foregroundStyle(.secondary)
                    Text(current.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if tab != "versions" {
                    Button(D.getVersions.localized) { tab = "versions" }.buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
            CatalogProjectFacts(project: current).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func overview(_ detail: CatalogDetail) -> some View {
        VStack(spacing: 0) {
            if !detail.links.isEmpty || detail.license != nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(detail.links) { link in Link(destination: link.url) { Label(link.title, systemImage: link.symbol) } }
                        if let license = detail.license { Label(license, systemImage: "doc.text").foregroundStyle(.secondary) }
                    }.font(.callout).padding(.horizontal, 24).padding(.vertical, 12)
                }
                Divider()
            }
            if detail.body.isEmpty { ContentUnavailableView(D.noDescription.localized, systemImage: "doc.text") }
            else { CatalogDocumentView(text: detail.body, isHTML: detail.isHTML, baseURL: current.pageURL) }
        }
    }
    private func gallery(_ detail: CatalogDetail) -> some View {
        ScrollView {
            if detail.gallery.isEmpty {
                ContentUnavailableView(D.noGallery.localized, systemImage: "photo.on.rectangle.angled").padding(24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                    ForEach(detail.gallery) { image in
                        VStack(alignment: .leading, spacing: 8) {
                            Link(destination: image.url) {
                                AsyncImage(url: image.url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFit() }
                                    else if phase.error != nil { Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).frame(maxWidth: .infinity, minHeight: 180) }
                                    else { ProgressView().frame(maxWidth: .infinity, minHeight: 180) }
                                }.clipShape(RoundedRectangle(cornerRadius: 12))
                            }.help(D.openImage.localized)
                            if let title = image.title, !title.isEmpty { Text(title).font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                }.padding(24)
            }
        }
    }
}

struct CatalogVersionsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let project: CatalogProject
    var refreshToken = 0
    @State private var consumedRefresh = 0
    @State private var game = ""
    @State private var loader = ""
    @State private var channel = ""
    @State private var search = ""
    @State private var versions: [CatalogVersion] = []
    @State private var total = 0
    @State private var loadedCount = 0
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var nextPage = 0
    @State private var consumedPage = 0
    @State private var consumedVersionRetry = 0
    @State private var requestToken = UUID()
    @State private var initialized = false
    @State private var loadedQuery: String?
    @State private var installVersion: CatalogVersion?
    @State private var infoVersion: CatalogVersion?
    @State private var referenceInstanceID: UUID?
    @State private var collapsedGroups: Set<String> = []
    private var queryID: String { [project.id, game, loader].joined(separator: "|") }
    private var installedInstances: [GameInstance] { model.state.instances.filter(\.installed) }
    private var referenceInstance: GameInstance? { installedInstances.first { $0.id == referenceInstanceID } }
    private func matchesFilters(_ instance: GameInstance) -> Bool {
        game == instance.gameVersion && loader == (project.type == "mod" ? instance.loader.modrinthLoader : "")
    }
    private var visible: [CatalogVersion] { versions.filter { version in
        let instanceMatches = referenceInstance.map { version.supports($0, type: project.type) } ?? true
        return instanceMatches && (channel.isEmpty || version.channel == channel) && (search.isEmpty || version.name.localizedCaseInsensitiveContains(search) || version.filename.localizedCaseInsensitiveContains(search))
    } }
    private struct VersionGroup: Identifiable {
        let id: String
        let versions: [CatalogVersion]
    }
    private var groupedVersions: [VersionGroup] {
        let grouped = Dictionary(grouping: visible) {
            CatalogMetadata.sortedVersions($0.gameVersions).first ?? D.versionsUnknown.localized
        }
        return CatalogMetadata.sortedVersions(Array(grouped.keys)).map {
            VersionGroup(id: $0, versions: grouped[$0] ?? [])
        }
    }
    var body: some View {
        let groups = groupedVersions
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        HStack(spacing: 10) { filters }.fixedSize()
                        Spacer(minLength: 0)
                        versionSearch.frame(width: 260)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        WrappingLayout(spacing: 10) { filters }.frame(maxWidth: .infinity, alignment: .leading)
                        versionSearch
                    }
                }
                if let instance = referenceInstance {
                    CatalogInstanceFilterContext(instance: instance) { selectReference(nil) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.bottom, 16)
            if let error { CatalogErrorBanner(message: error) { retry += 1 }.padding(.horizontal, 24).padding(.bottom, 16) }
            if loading && versions.isEmpty { ProgressView(D.loadingVersions.localized).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if groups.isEmpty && !loading {
                            ContentUnavailableView(D.noVersions.localized, systemImage: "line.3.horizontal.decrease", description: Text(D.noVersionsHint.localized)).frame(maxWidth: .infinity)
                        }
                        if !groups.isEmpty {
                            Surface(padding: 0, shadow: false) {
                                LazyVStack(spacing: 0) {
                                    ForEach(groups) { group in
                                        CatalogVersionGroup(
                                            title: D.minecraftVersion(group.id).localized,
                                            versions: group.versions,
                                            isExpanded: Binding(get: { !collapsedGroups.contains(group.id) }, set: { expanded in
                                                if expanded { collapsedGroups.remove(group.id) }
                                                else { collapsedGroups.insert(group.id) }
                                            }),
                                            canAcquire: !model.busy && !model.readOnly,
                                            onDetails: { infoVersion = $0 }, onAcquire: { installVersion = $0 }
                                        )
                                        if group.id != groups.last?.id { Divider() }
                                    }
                                }
                            }
                        }
                        HStack {
                            Text(D.loadedVersions(Int64(loadedCount), Int64(total)).localized).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if loading { ProgressView().controlSize(.small) }
                            else if loadedCount < total {
                                Button(D.loadMore.localized) { nextPage += 1 }
                            }
                        }.padding(.vertical, 12)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }
        .background(Theme.canvas(for: colorScheme))
        .task(id: queryID) {
            let initialKey = queryID
            if !initialized {
                initialized = true
                game = model.discovery.query.game
                loader = model.discovery.query.loader
                if project.type != "modpack", let instance = installedInstances.first(where: { $0.id == model.discovery.preferredInstanceID }), matchesFilters(instance) {
                    referenceInstanceID = instance.id
                }
                if queryID != initialKey { return }
            }
            if loadedQuery != queryID || versions.isEmpty { await load(reset: true) }
        }
        .onChange(of: queryID) {
            collapsedGroups.removeAll()
            if let instance = referenceInstance, !matchesFilters(instance) { referenceInstanceID = nil }
        }
        .onChange(of: search) { collapsedGroups.removeAll() }
        .onChange(of: channel) { collapsedGroups.removeAll() }
        .onChange(of: referenceInstanceID) { collapsedGroups.removeAll() }
        .onChange(of: referenceInstance) { before, after in
            guard before?.id == after?.id, let after else { return }
            game = after.gameVersion; loader = project.type == "mod" ? after.loader.modrinthLoader : ""
        }
        .task(id: retry) { if retry > consumedVersionRetry { consumedVersionRetry = retry; await load(reset: versions.isEmpty, refresh: true) } }
        .task(id: nextPage) { if nextPage > consumedPage { consumedPage = nextPage; await load(reset: false) } }
        .task(id: refreshToken) {
            if refreshToken > consumedRefresh { consumedRefresh = refreshToken; await load(reset: true, refresh: true) }
        }
        .sheet(item: $installVersion) { version in CatalogInstallView(project: project, version: version) }
        .sheet(item: $infoVersion) { version in
            CatalogReleaseInfo(project: project, version: version, onOpenProject: { dependency in
                infoVersion = nil
                model.discovery.open(dependency)
            })
        }
    }
    private var versionSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(D.searchLoadedVersions.localized, text: $search).textFieldStyle(.plain)
        }.padding(.horizontal, 10).frame(height: 34)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.075)))
    }
    @ViewBuilder private var filters: some View {
        CatalogGameFilter(selection: $game, versions: project.gameVersions.isEmpty ? (model.catalog?.versions ?? []).filter(\.isRelease).map(\.id) : project.gameVersions).frame(width: 180)
        if project.type == "mod" || project.type == "modpack" {
            CatalogLoaderFilter(selection: $loader, loaders: project.loaders + ["fabric", "forge", "neoforge", "quilt"]).frame(width: 180)
        }
        CatalogMenuFilter(title: D.releaseChannel.localized, value: channel.isEmpty ? D.unrestricted.localized : channel == "release" ? D.release.localized : channel.capitalized, symbol: "tag", active: !channel.isEmpty) {
            Picker(D.releaseChannel.localized, selection: $channel) {
                Text(D.allChannels.localized).tag("")
                Text(D.release.localized).tag("release")
                Text("Beta").tag("beta")
                Text("Alpha").tag("alpha")
            }.pickerStyle(.inline).labelsHidden()
        }.frame(width: 160)
        if project.type != "modpack", !installedInstances.isEmpty {
            CatalogMenuFilter(title: D.filterByInstance.localized, value: referenceInstance?.name ?? D.unrestricted.localized, symbol: "desktopcomputer", active: referenceInstance != nil) {
                Picker(D.filterByInstance.localized, selection: Binding(get: { referenceInstanceID }, set: { selectReference($0) })) {
                    Text(D.noInstanceFilter.localized).tag(nil as UUID?)
                    ForEach(installedInstances) { instance in
                        Label { Text(instance.name + " · " + instance.subtitle) } icon: {
                            LoaderGlyph.image(for: instance.loader.modrinthLoader).resizable().scaledToFit().frame(width: 16, height: 16)
                        }.tag(Optional(instance.id))
                    }
                }.pickerStyle(.inline).labelsHidden().labelStyle(.titleAndIcon)
                Divider()
                Text(D.instanceFilterHint.localized)
            }.frame(width: 210)
        }
    }
    private func selectReference(_ id: UUID?) {
        referenceInstanceID = id
        if let instance = installedInstances.first(where: { $0.id == id }) {
            game = instance.gameVersion
            loader = project.type == "mod" ? instance.loader.modrinthLoader : ""
            model.discovery.preferredInstanceID = instance.id
        } else { game = ""; loader = "" }
    }
    private func load(reset: Bool, refresh: Bool = false) async {
        let key = queryID
        let token = UUID(); requestToken = token
        if reset { versions = []; loadedCount = 0; total = 0; search = ""; collapsedGroups.removeAll() }
        let offset = reset ? 0 : loadedCount
        loading = true; error = nil
        defer { if requestToken == token { loading = false } }
        do {
            let page = try await model.catalogRepository.versions(project, game: game, loader: loader, offset: offset, refresh: refresh)
            try Task.checkCancellation(); guard key == queryID, requestToken == token else { return }
            let existing = Set(versions.map(\.id))
            versions.append(contentsOf: page.versions.filter { !existing.contains($0.id) })
            loadedCount = page.versions.isEmpty ? max(offset, page.total) : offset + page.versions.count
            total = page.total; loadedQuery = key
        } catch { if !Task.isCancelled && key == queryID && requestToken == token { self.error = error.localizedDescription } }
    }
}
