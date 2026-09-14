import RuriLocalization
import SwiftUI
import RuriCore

private typealias D = Messages.Discovery

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var categories: [CatalogCategory] = []
    @State private var categoryError: String?
    @State private var refresh = 0
    @State private var categoryRetry = 0
    @State private var consumedRefresh = 0
    private var browser: CatalogBrowser { model.discovery }
    private var missingKey: Bool { browser.query.source == .curseforge && !model.curseForgeConfigured }
    private var filterInstance: GameInstance? {
        guard browser.query.type != "modpack", let instance = model.state.instances.first(where: { $0.id == browser.preferredInstanceID }),
              browser.query.game == instance.gameVersion,
              browser.query.loader == (browser.query.type == "mod" ? instance.loader.modrinthLoader : "") else { return nil }
        return instance
    }
    var body: some View {
        @Bindable var browser = browser
        NavigationStack(path: $browser.path) {
            browse
                .navigationDestination(for: CatalogProject.self) { project in CatalogDetailView(project: project) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let activity = model.activeActivity {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 12) {
                        if activity.progress.total > 0 { ProgressView(value: activity.progress.fraction).frame(width: 100) }
                        else { ProgressView().controlSize(.small) }
                        Text(activity.progress.stage).font(.callout).lineLimit(1)
                        Spacer()
                        Button(D.viewDownloads.localized) { model.page = .activity }
                    }.padding(.horizontal, 24).padding(.vertical, 12)
                }.background(.bar)
            }
        }
    }
    private var browse: some View {
        @Bindable var browser = browser
        return VStack(spacing: 0) {
            controls.padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            if missingKey {
                ContentUnavailableView {
                    Label(Messages.AppDiscoverView.connectCurseForge.localized, systemImage: "key")
                } description: {
                    Text(Messages.AppDiscoverView.curseforgeSetupDetails.localized)
                } actions: {
                    Button(Messages.AppDiscoverView.goToSettings.localized) { model.page = .settings }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                results
            }
        }
        .navigationTitle(Messages.AppPage.discover.localized)
        .searchable(text: field(\.text), placement: .toolbar, prompt: Messages.AppDiscoverView.searchContent.localized)
        .searchSuggestions {
            if browser.query.text.isEmpty {
                ForEach(browser.recentSearches, id: \.self) { term in
                    Label(term, systemImage: "clock").searchCompletion(term)
                }
            }
        }
        .onSubmit(of: .search) { browser.rememberSearch() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showCreate = true } label: { Label(D.downloadGame.localized, systemImage: "plus") }
                    .help(D.downloadGame.localized).disabled(model.busy || model.readOnly)
                Button { model.chooseInstanceImport() } label: { Label(Messages.AppDiscoverView.importModpack.localized, systemImage: "square.and.arrow.down") }
                    .help(Messages.AppDiscoverView.importLocalModpack.localized).disabled(model.busy || model.readOnly)
                Button { refresh += 1 } label: { Label(D.refresh.localized, systemImage: "arrow.clockwise") }
                    .help(D.refresh.localized).disabled(browser.loading || missingKey)
            }
        }
        .task(id: browser.query) { await load() }
        .task(id: refresh) { if refresh > consumedRefresh { consumedRefresh = refresh; await load(force: true) } }
        .onChange(of: model.curseForgeConfigured) { refresh += 1 }
        .task(id: "\(browser.query.source.rawValue):\(model.curseForgeConfigured):\(categoryRetry)") {
            categories = []; categoryError = nil
            guard !missingKey else { return }
            do {
                let result = try await model.catalogRepository.categories(source: browser.query.source)
                try Task.checkCancellation(); categories = result
            } catch { if !Task.isCancelled { categoryError = error.localizedDescription } }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { contentPicker.fixedSize(); Spacer(minLength: 0); sourcePicker.frame(width: 192) }
                VStack(alignment: .leading, spacing: 12) { contentPicker; sourcePicker.frame(width: 192) }
            }
            CatalogWrappingLayout(spacing: 10) {
                gameFilter
                loaderFilter
                categoryFilter
                resetFilters
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let instance = filterInstance {
                CatalogInstanceFilterContext(instance: instance) {
                    browser.change { $0.game = ""; $0.loader = "" }
                    browser.preferredInstanceID = nil
                }
            }
            if let categoryError {
                HStack {
                    Text(D.categoriesUnavailable.localized).font(.caption).foregroundStyle(.secondary).help(categoryError)
                    Button(Messages.AppDiscoverView.retry.localized) { categoryRetry += 1 }.font(.caption)
                }
            }
        }
    }
    private var contentPicker: some View {
        Picker(Messages.AppDiscoverView.contentType.localized, selection: Binding(get: { browser.query.type }, set: { type in
            switchCollection(type: type)
        })) {
            Text(Messages.AppDiscoverView.modpacks.localized).tag("modpack")
            Text(Messages.AppDiscoverView.mods.localized).tag("mod")
            Text(Messages.AppDiscoverView.resourcePacks.localized).tag("resourcepack")
            Text(Messages.AppDiscoverView.shaders.localized).tag("shader")
        }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(Messages.AppDiscoverView.contentType.localized)
    }
    private var sourcePicker: some View {
        Picker(Messages.AppDiscoverView.contentSource.localized, selection: Binding(get: { browser.query.source }, set: { source in
            switchCollection(source: source)
        })) { ForEach(CatalogSource.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
    }
    private var gameFilter: some View {
        CatalogGameFilter(selection: field(\.game), versions: (model.catalog?.versions ?? []).filter(\.isRelease).map(\.id))
            .frame(width: 180)
    }
    @ViewBuilder private var loaderFilter: some View {
        if ["mod", "modpack"].contains(browser.query.type) {
            CatalogLoaderFilter(selection: field(\.loader)).frame(width: 180)
        }
    }
    private var categoryFilter: some View {
        let selected = categories.first { $0.id == browser.query.category && $0.type == browser.query.type }
        return CatalogMenuFilter(title: D.category.localized, value: selected.map { CatalogCategoryPresentation.title($0.name) } ?? D.unrestricted.localized, symbol: "tag", active: !browser.query.category.isEmpty) {
            Picker(D.category.localized, selection: field(\.category)) {
                Text(D.allCategories.localized).tag("")
                ForEach(categories.filter { $0.type == browser.query.type }.sorted { $0.name < $1.name }) { Text(CatalogCategoryPresentation.title($0.name)).tag($0.id) }
            }.pickerStyle(.inline).labelsHidden()
        }.frame(width: 180)
    }
    @ViewBuilder private var resetFilters: some View {
        if browser.query.hasFilters {
            Button(D.clearFilters.localized) { browser.change { $0.game = ""; $0.loader = ""; $0.category = "" } }.buttonStyle(.link)
        }
    }
    private var results: some View {
        @Bindable var browser = browser
        return VStack(spacing: 0) {
            HStack {
                if let page = browser.page { Text(D.resultCount(Int64(page.total)).localized).font(.callout).foregroundStyle(.secondary) }
                if browser.loading { ProgressView().controlSize(.small).accessibilityLabel(D.searching.localized) }
                Spacer()
                Picker(D.sort.localized, selection: field(\.sort)) {
                    ForEach(CatalogSort.allCases.filter { browser.query.source == .modrinth || $0 != .relevance }) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize()
                Picker(D.layout.localized, selection: $browser.listLayout) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 68)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            if let error = browser.error {
                CatalogErrorBanner(message: error) { refresh += 1 }.padding(.horizontal, 24).padding(.bottom, 12)
            }
            if browser.error != nil, browser.page != nil, browser.query.normalized != browser.displayedQuery {
                Text(D.showingPreviousResults.localized).font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            if browser.page == nil && browser.loading {
                ProgressView(D.searching.localized).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page = browser.page, page.projects.isEmpty {
                ContentUnavailableView.search(text: browser.displayedQuery?.text ?? "").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: browser.listLayout ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                        ForEach(browser.page?.projects ?? []) { project in
                            Button {
                                browser.rememberSearch(); browser.open(project)
                            } label: { CatalogProjectCard(project: project, compact: browser.listLayout) }
                                .buttonStyle(.plain).id(project.id)
                        }
                    }.scrollTargetLayout().padding(.horizontal, 24).padding(.bottom, 24)
                }
                .scrollPosition(id: $browser.scrollID, anchor: .top)
            }
            if let page = browser.page, !page.projects.isEmpty {
                Divider()
                HStack(spacing: 12) {
                    let offset = browser.displayedQuery?.offset ?? 0
                    Text(D.pageRange(Int64(offset + 1), Int64(offset + page.projects.count), Int64(page.total)).localized).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button { browser.query.offset = max(0, offset - 20); browser.scrollID = nil } label: { Label(Messages.AppDiscoverView.previousPage.localized, systemImage: "chevron.left") }
                        .disabled(offset == 0 || browser.loading || browser.query.normalized != browser.displayedQuery)
                    Button { browser.query.offset = offset + 20; browser.scrollID = nil } label: { Label(Messages.AppDiscoverView.nextPage.localized, systemImage: "chevron.right") }
                        .disabled(offset + page.projects.count >= page.total || browser.loading || browser.query.normalized != browser.displayedQuery)
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
    }
    private func switchCollection(source: CatalogSource? = nil, type: String? = nil) {
        let instance = filterInstance
        browser.switchCollection(source: source, type: type)
        if let instance, browser.query.type != "modpack" {
            let loader = browser.query.type == "mod" ? instance.loader.modrinthLoader : ""
            if browser.query.game != instance.gameVersion || browser.query.loader != loader {
                browser.change { query in query.game = instance.gameVersion; query.loader = loader }
            }
            browser.preferredInstanceID = instance.id
        }
    }
    private func field<Value>(_ key: WritableKeyPath<CatalogQuery, Value>) -> Binding<Value> {
        Binding(get: { browser.query[keyPath: key] }, set: { value in browser.change { $0[keyPath: key] = value } })
    }
    private func load(force: Bool = false) async {
        guard !missingKey else { return }
        let repository = model.catalogRepository
        await browser.load(refresh: force) { try await repository.search($0) }
    }
}
