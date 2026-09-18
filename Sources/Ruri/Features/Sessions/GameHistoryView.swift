import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

/// A player's own record of what they have played, laid out like a Replay or
/// a Fitness summary rather than a report: one big number and the facts
/// under it, the highlights of the stretch, then the instances and saves as
/// tiles they can filter by, and finally every run, day by day. The logs
/// behind a bad run stay a level deeper, in the run's own sheet. Queries are
/// paged and run off the UI actor, including when an instance has since been
/// deleted.
struct GameHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let cache: Cache

    @MainActor final class Cache {
        let overviews = ViewSnapshotCache<OverviewKey, GameHistoryOverview>()
        let runs = ViewSnapshotCache<RunsKey, RunsSnapshot>()
        let worldIcons = ViewSnapshotCache<String, NSImage>(capacity: 128)
    }

    struct OverviewKey: Hashable {
        let instanceID: UUID?
        let range: GameHistoryRange
        var day = Calendar.current.startOfDay(for: .now)
        var calendar = Calendar.current
    }

    struct RunsKey: Hashable {
        let overview: OverviewKey
        var worldFolder: String?
        var search = ""
        var problemsOnly = false
    }

    struct RunsSnapshot {
        let records: [GameSession]
        let hasMore: Bool
    }

    private enum Span: String, CaseIterable, Identifiable {
        case week, month, year, all
        var id: String { rawValue }
        var short: String {
            switch self {
            case .week: Messages.HistoryUI.rangeWeek.localized
            case .month: Messages.HistoryUI.rangeMonth.localized
            case .year: Messages.HistoryUI.rangeYear.localized
            case .all: Messages.HistoryUI.rangeAll.localized
            }
        }
        var title: String {
            switch self {
            case .week: Messages.HistoryUI.rangeWeekTitle.localized
            case .month: Messages.HistoryUI.rangeMonthTitle.localized
            case .year: Messages.HistoryUI.rangeYearTitle.localized
            case .all: Messages.HistoryUI.rangeAllTitle.localized
            }
        }
        /// The stretch just before this one, for the comparison line.
        var previousTitle: String? {
            switch self {
            case .week: Messages.HistoryUI.previousWeek.localized
            case .month: Messages.HistoryUI.previousMonth.localized
            case .year: Messages.HistoryUI.previousYear.localized
            case .all: nil
            }
        }
        var query: GameHistoryRange {
            switch self {
            case .week: .days(7)
            case .month: .days(30)
            case .year: .months(12)
            case .all: .all
            }
        }
        /// The same boundary the overview uses, so the timeline below never
        /// lists a run the chart above does not count.
        var since: Date? {
            let calendar = Calendar.current, now = Date()
            switch self {
            case .week: return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
            case .month: return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
            case .year:
                let month = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? calendar.startOfDay(for: now)
                return calendar.date(byAdding: .month, value: -11, to: month)
            case .all: return nil
            }
        }
    }

    /// One save whose `icon.png` the page wants to show.
    private struct WorldIconRequest: Hashable, Sendable {
        let key: String
        let instanceID: UUID
        let folder: String
    }

    @State private var span = Span.month
    @State private var overview = GameHistoryOverview()
    @State private var records: [GameSession] = []
    @State private var world: GameHistoryTotal?
    @State private var search = ""
    @State private var problemsOnly = false
    @State private var loadingRuns = false
    @State private var overviewResolved = false
    @State private var runsResolved = false
    @State private var previousSearch = ""
    @State private var hasMore = false
    @State private var error: String?
    @State private var request = UUID()
    @State private var worldIcons: [String: NSImage] = [:]
    @State private var worldIconsChecked: Set<String> = []
    @State private var chartSelection: Date?
    /// The first fill of the page is not a change worth animating; only a
    /// later range or filter switch rolls the numbers over.
    @State private var settled = false

    init(cache: Cache, instanceID: UUID?) {
        self.cache = cache
        let key = OverviewKey(instanceID: instanceID, range: Span.month.query)
        let overview = cache.overviews[key]
        let runs = cache.runs[RunsKey(overview: key)]
        _overview = State(initialValue: overview ?? GameHistoryOverview())
        _records = State(initialValue: runs?.records ?? [])
        _hasMore = State(initialValue: runs?.hasMore ?? false)
        _overviewResolved = State(initialValue: overview != nil)
        _runsResolved = State(initialValue: runs != nil)
        var icons: [String: NSImage] = [:]
        for total in overview?.worlds ?? [] {
            icons[total.id] = cache.worldIcons[total.id]
        }
        for record in runs?.records ?? [] {
            if let folder = record.world?.folder {
                let key = record.instanceID.uuidString + "/" + folder
                icons[key] = cache.worldIcons[key]
            }
        }
        _worldIcons = State(initialValue: icons)
    }

    private var instanceID: UUID? { world?.instanceID ?? model.historyInstanceID }
    private var filtered: Bool { model.historyInstanceID != nil || world != nil || problemsOnly || !search.trimmed.isEmpty }
    private var overviewKey: String { "\(model.historyInstanceID?.uuidString ?? "")|\(span.rawValue)|\(model.historyRevision)|\(request)" }
    private var runsKey: String { "\(instanceID?.uuidString ?? "")|\(world?.folder ?? "")|\(span.rawValue)|\(search)|\(problemsOnly)|\(model.historyRevision)|\(request)" }
    private var overviewCacheKey: OverviewKey { .init(instanceID: model.historyInstanceID, range: span.query) }
    private var runsCacheKey: RunsKey {
        .init(overview: .init(instanceID: instanceID, range: span.query), worldFolder: world?.folder, search: search, problemsOnly: problemsOnly)
    }
    private var isBlank: Bool { overviewResolved && runsResolved && overview.playCount == 0 && records.isEmpty }
    private var showsEmptyState: Bool { isBlank && !filtered }

    var body: some View {
        Group {
            if overviewResolved && runsResolved {
                history
            } else {
                DelayedProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas(for: colorScheme))
        .searchable(text: $search, prompt: Text(Messages.SessionUI.search.localized))
        .toolbar { filterMenu }
        .task(id: overviewKey) { await loadOverview() }
        .task(id: runsKey) { await loadRuns() }
        .task(id: worldIconKey) { await loadWorldIcons() }
        .onChange(of: span) { chartSelection = nil }
    }

    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                if !showsEmptyState {
                    VStack(alignment: .leading, spacing: 32) {
                        activity
                        highlights
                        instancesSection
                        worldsSection
                        timeline
                        if let error = error ?? model.historyStorageError { failure(error) }
                    }
                    .padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 32)
                    .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
                } else if let error = error ?? model.historyStorageError {
                    failure(error).padding(.horizontal, 28).frame(maxWidth: 1040).frame(maxWidth: .infinity)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .softTopScrollEdge()
    }

    // MARK: Header

    private var hero: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { headline; Spacer(minLength: 16); spanPicker.padding(.top, 4) }
                VStack(alignment: .leading, spacing: 18) { headline; spanPicker }
            }
            if !showsEmptyState {
                stats
                if filtered { chips }
            }
        }
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 24)
        .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(span.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .contentTransition(.opacity).animation(.easeInOut(duration: 0.2), value: span)
            if showsEmptyState {
                Text(Messages.SessionUI.noHistory.localized).font(.system(size: 34, weight: .bold, design: .rounded))
                Text(Messages.SessionUI.noHistoryHelp.localized).font(.callout).foregroundStyle(.secondary)
            } else {
                Text(LocalizedFormat.duration(overview.seconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitle: String {
        if span == .all, let first = overview.firstPlayed {
            return Messages.HistoryUI.sinceFirstPlay(LocalizedFormat.date(first, time: .omitted)).localized
        }
        if let last = overview.lastPlayed { return Messages.HistoryUI.lastPlayed(LocalizedFormat.relative(last)).localized }
        return " "
    }

    private var spanPicker: some View {
        Picker(Messages.SessionUI.date.localized, selection: $span) {
            ForEach(Span.allCases) { Text($0.short).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        .accessibilityLabel(Messages.SessionUI.date.localized)
    }

    /// A row of equal facts split by hairlines, like the strip under an App
    /// Store title. It scrolls sideways when the page is too narrow.
    private var stats: some View {
        ViewThatFits(in: .horizontal) {
            statsRow(expanded: true)
            ScrollView(.horizontal, showsIndicators: false) { statsRow(expanded: false) }
        }
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func statsRow(expanded: Bool) -> some View {
        HStack(spacing: 0) {
            HeroStat(label: Messages.SessionUI.playCount.localized, value: Messages.HistoryUI.sessionCount(Int64(overview.playCount)).localized) {
                Text(overview.lastPlayed.map(LocalizedFormat.relative) ?? " ")
            }
            Divider().frame(height: 40)
            HeroStat(label: Messages.HistoryUI.activeDays.localized, value: Messages.HistoryUI.dayCount(Int64(overview.activeDays)).localized) {
                Text(" ")
            }
            Divider().frame(height: 40)
            HeroStat(label: Messages.HistoryUI.averageSession.localized, value: LocalizedFormat.duration(overview.averageSeconds)) {
                Text(overview.longestSeconds > 0 ? Messages.HistoryUI.longestSession.localized + " " + LocalizedFormat.duration(overview.longestSeconds) : " ")
            }
            Divider().frame(height: 40)
            HeroStat(label: Messages.HistoryUI.streak.localized, value: Messages.HistoryUI.dayCount(Int64(overview.streakDays)).localized) {
                WeekDots(played: overview.recentDays)
            }
        }
        .padding(.vertical, 12)
        .environment(\.heroStatExpanded, expanded)
    }

    /// The active filters, each removable in place, so a narrowed page never
    /// looks like the whole history shrank.
    private var chips: some View {
        WrappingLayout(spacing: 8) {
            if let id = model.historyInstanceID, world == nil {
                let name = overview.instances.first { $0.instanceID == id }?.title ?? model.state.instances.first { $0.id == id }?.name ?? Messages.SessionUI.instance.localized
                FilterChip(text: Messages.HistoryUI.filteredByInstance(name).localized) { model.historyInstanceID = nil }
            }
            if let world {
                FilterChip(text: Messages.HistoryUI.filteredByWorld(world.title).localized) { self.world = nil }
            }
            if problemsOnly {
                FilterChip(text: Messages.SessionUI.problemsOnly.localized) { problemsOnly = false }
            }
        }
    }

    @ToolbarContentBuilder private var filterMenu: some ToolbarContent {
        ToolbarItem {
            @Bindable var model = model
            Menu {
                Picker(Messages.SessionUI.instance.localized, selection: $model.historyInstanceID) {
                    Text(Messages.SessionUI.allInstances.localized).tag(Optional<UUID>.none)
                    ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                }
                if world != nil {
                    Button(Messages.HistoryUI.allWorlds.localized) { world = nil }
                }
                Toggle(Messages.SessionUI.problemsOnly.localized, isOn: $problemsOnly)
                if filtered {
                    Divider()
                    Button(Messages.HistoryUI.clearFilters.localized, systemImage: "xmark.circle") {
                        model.historyInstanceID = nil; world = nil; problemsOnly = false; search = ""
                    }
                }
            } label: {
                Label(Messages.HistoryUI.filters.localized, systemImage: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .help(Messages.HistoryUI.filters.localized)
        }
    }

    // MARK: Activity

    private var activity: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Messages.HistoryUI.activity.localized).font(.title3.weight(.semibold))
                    Spacer()
                    activityCaption
                        .font(.callout)
                        .animation(.easeOut(duration: 0.15), value: chartSelection)
                }
                GameActivityChart(buckets: overview.buckets, daily: overview.daily, selection: $chartSelection)
                    .id(span)
                    .transition(.opacity)
            }
        }
    }

    /// The hovered column's own numbers, or otherwise how this stretch
    /// compares with the one before it, in the manner of Screen Time.
    @ViewBuilder private var activityCaption: some View {
        if let bucket = GameActivityChart.bucket(for: chartSelection, in: overview.buckets, daily: overview.daily) {
            HStack(spacing: 6) {
                Text(GameActivityChart.label(bucket.date, daily: overview.daily)).foregroundStyle(.secondary)
                Text(LocalizedFormat.duration(bucket.seconds)).fontWeight(.semibold).monospacedDigit()
                if bucket.count > 0 {
                    Text("·").foregroundStyle(.secondary)
                    Text(Messages.HistoryUI.sessionCount(Int64(bucket.count)).localized).foregroundStyle(.secondary)
                }
            }
            .transition(.opacity)
        } else if let comparison {
            Label(comparison.text, systemImage: comparison.symbol)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .transition(.opacity)
        }
    }

    private var comparison: (text: String, symbol: String)? {
        guard let previous = overview.previousSeconds, let period = span.previousTitle, overview.seconds > 0 || previous > 0 else { return nil }
        let delta = overview.seconds - previous
        if abs(delta) < 60 { return (Messages.HistoryUI.sameAsPrevious(period).localized, "equal") }
        return delta > 0
            ? (Messages.HistoryUI.moreThanPrevious(period, LocalizedFormat.duration(delta)).localized, "arrow.up.right")
            : (Messages.HistoryUI.lessThanPrevious(period, LocalizedFormat.duration(-delta)).localized, "arrow.down.right")
    }

    // MARK: Highlights

    /// The three things worth remembering about the stretch.
    @ViewBuilder private var highlights: some View {
        let top = overview.instances.first, favorite = overview.worlds.first, longest = overview.longest
        if top != nil || favorite != nil || longest != nil {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    if let top {
                        HighlightCard(kicker: Messages.HistoryUI.mostPlayed.localized, title: top.title,
                                      detail: LocalizedFormat.duration(top.seconds) + " · " + Messages.HistoryUI.shareOfRange(LocalizedFormat.percent(share(top.seconds))).localized,
                                      help: Messages.HistoryUI.showRuns.localized) {
                            world = nil; model.historyInstanceID = top.instanceID
                        } icon: {
                            instanceIcon(top.instanceID, size: 56)
                        }
                    }
                    if let favorite {
                        HighlightCard(kicker: Messages.HistoryUI.favoriteWorld.localized, title: favorite.title,
                                      detail: LocalizedFormat.duration(favorite.seconds) + (favorite.subtitle.map { " · " + $0 } ?? ""),
                                      help: Messages.HistoryUI.showRuns.localized) {
                            world = favorite
                        } icon: {
                            WorldIcon(image: worldIcons[favorite.id], size: 56)
                        }
                    }
                    if let longest, longest.playedSeconds > 0 {
                        HighlightCard(kicker: Messages.HistoryUI.longestSession.localized, title: LocalizedFormat.duration(longest.playedSeconds),
                                      detail: longest.instanceName + " · " + LocalizedFormat.date(longest.startDate, time: .omitted),
                                      help: Messages.SessionUI.details.localized) {
                            model.inspectSession(longest)
                        } icon: {
                            instanceIcon(longest.instanceID, size: 56)
                        }
                    }
                }
            }
        }
    }

    // MARK: Instances and saves

    @ViewBuilder private var instancesSection: some View {
        if !overview.instances.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Messages.HistoryUI.instancesSection.localized) {
                    if overview.instances.count > 8 {
                        Text(Messages.HistoryUI.otherInstances(Int64(overview.instances.count - 8)).localized).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(overview.instances.prefix(8))) { total in
                        RankTile(total: total, share: share(total.seconds),
                                 subtitle: total.lastPlayed.map(LocalizedFormat.relative),
                                 selected: model.historyInstanceID == total.instanceID && world == nil) {
                            if model.historyInstanceID == total.instanceID && world == nil { model.historyInstanceID = nil }
                            else { world = nil; model.historyInstanceID = total.instanceID }
                        } icon: {
                            instanceIcon(total.instanceID, size: 40)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var worldsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.HistoryUI.worldsSection.localized)
            if overview.worlds.isEmpty {
                Surface(padding: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "globe.asia.australia").font(.system(size: 24)).foregroundStyle(.tertiary).accessibilityHidden(true)
                        Text(Messages.HistoryUI.noWorldsHelp.localized)
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(Array(overview.worlds.prefix(8))) { total in
                        RankTile(total: total, share: share(total.seconds), subtitle: total.subtitle, selected: world?.id == total.id) {
                            world = world?.id == total.id ? nil : total
                        } icon: {
                            WorldIcon(image: worldIcons[total.id], size: 40)
                        }
                    }
                }
            }
        }
    }

    private func share(_ seconds: Double) -> Double {
        overview.seconds > 0 ? seconds / overview.seconds : 0
    }

    // MARK: Timeline

    /// Every run, one card per day, with the day's runs drawn on a 24-hour
    /// track so an evening of play looks different from a morning of it.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.HistoryUI.timelineSection.localized) {
                if loadingRuns && !records.isEmpty { DelayedProgressView().controlSize(.small) }
            }
            if records.isEmpty {
                Surface(padding: 0) {
                    Text(filtered ? Messages.SessionUI.noMatches.localized : Messages.SessionUI.noHistoryHelp.localized)
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                }
            }
            ForEach(days, id: \.day) { group in
                dayCard(group.day, records: group.records)
            }
            if hasMore {
                Button(Messages.SessionUI.loadMore.localized) { Task { await loadMore() } }
                    .buttonStyle(.link).disabled(loadingRuns)
                    .padding(.horizontal, 4)
            }
            Text(Messages.SessionRuntime.timingHelp.localized).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var days: [(day: Date, records: [GameSession])] {
        let calendar = Calendar.current
        var order: [Date] = []
        var grouped: [Date: [GameSession]] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.startDate)
            if grouped[day] == nil { order.append(day) }
            grouped[day, default: []].append(record)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private func dayCard(_ day: Date, records: [GameSession]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(dayTitle(day)).font(.headline)
                Spacer()
                Text(LocalizedFormat.duration(records.reduce(0) { $0 + $1.playedSeconds }))
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 4)
            Surface(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    DayTrack(day: day, records: records)
                        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
                    ForEach(records) { record in
                        Divider().padding(.leading, record.id == records.first?.id ? 0 : 66)
                        HistoryRunRow(record: record, instance: model.state.instances.first { $0.id == record.instanceID },
                                      worldIcon: record.world.map { worldIcons[record.instanceID.uuidString + "/" + $0.folder] } ?? nil) {
                            model.inspectSession(record)
                        }
                    }
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Messages.HistoryUI.today.localized }
        if calendar.isDateInYesterday(day) { return Messages.HistoryUI.yesterday.localized }
        let style = Date.FormatStyle(locale: LocalizationContext.current.formatLocale)
        return calendar.isDate(day, equalTo: Date(), toGranularity: .year)
            ? day.formatted(style.month(.wide).day().weekday(.abbreviated))
            : day.formatted(style.year().month(.wide).day())
    }

    private func failure(_ message: String) -> some View {
        HStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            Spacer(minLength: 8)
            Button(Messages.SessionUI.retry.localized) { request = UUID() }.controlSize(.small)
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Artwork

    @ViewBuilder private func instanceIcon(_ id: UUID?, size: CGFloat) -> some View {
        if let instance = model.state.instances.first(where: { $0.id == id }) {
            InstanceIcon(instance, size: size)
        } else {
            InstanceIcon(loader: .vanilla, size: size)
        }
    }

    private var worldIconRequests: [WorldIconRequest] {
        var seen = Set<String>(), result: [WorldIconRequest] = []
        for total in overview.worlds {
            guard let id = total.instanceID, let folder = total.folder, seen.insert(total.id).inserted else { continue }
            result.append(.init(key: total.id, instanceID: id, folder: folder))
        }
        for record in records {
            guard let folder = record.world?.folder else { continue }
            let key = record.instanceID.uuidString + "/" + folder
            if seen.insert(key).inserted { result.append(.init(key: key, instanceID: record.instanceID, folder: folder)) }
        }
        return result
    }

    private var worldIconKey: String { worldIconRequests.map(\.key).joined(separator: ",") }

    /// Saves keep a small `icon.png` next to their level data. Reading it is
    /// display only: a missing or oversized file just leaves the globe.
    private func loadWorldIcons() async {
        let wanted = worldIconRequests.filter { !worldIconsChecked.contains($0.key) }
        guard !wanted.isEmpty else { return }
        let paths = model.paths
        let loaded = await Task.detached(priority: .utility) { () -> [String: Data] in
            var result: [String: Data] = [:]
            for item in wanted {
                let saves = paths.game(item.instanceID).appendingPathComponent("saves", isDirectory: true)
                guard let url = try? LauncherPaths.safePath(item.folder + "/icon.png", within: saves),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1_048_576,
                      let data = try? Data(contentsOf: url) else { continue }
                result[item.key] = data
            }
            return result
        }.value
        guard !Task.isCancelled else { return }
        for item in wanted { worldIconsChecked.insert(item.key) }
        for (key, data) in loaded {
            if let image = NSImage(data: data) { worldIcons[key] = image; cache.worldIcons[key] = image }
        }
    }

    // MARK: Loading

    private func loadOverview() async {
        let generation = overviewKey, cacheKey = overviewCacheKey
        defer {
            if generation == overviewKey && !Task.isCancelled { overviewResolved = true }
        }
        let paths = model.paths, id = model.historyInstanceID, range = span.query
        let work = Task.detached(priority: .utility) { try GameHistoryStore.overview(paths: paths, instanceID: id, range: range) }
        do {
            let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            guard generation == overviewKey else { return }
            cache.overviews[cacheKey] = value
            if settled {
                withAnimation(.smooth(duration: 0.45)) { overview = value }
            } else {
                overview = value; settled = true
            }
            error = nil; model.historyStorageError = nil
            if let world, !value.worlds.contains(where: { $0.id == world.id }) { self.world = nil }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func loadRuns() async {
        let generation = runsKey, cacheKey = runsCacheKey
        let debounce = search != previousSearch
        previousSearch = search
        loadingRuns = true
        defer {
            if generation == runsKey {
                loadingRuns = false
                if !Task.isCancelled { runsResolved = true }
            }
        }
        let query = GameHistoryQuery(instanceID: instanceID, worldFolder: world?.folder, since: span.since,
                                     search: search, problemsOnly: problemsOnly, limit: 60)
        let paths = model.paths
        do {
            if debounce { try await Task.sleep(for: .milliseconds(180)) }
            let work = Task.detached(priority: .utility) { try GameHistoryStore.list(paths: paths, query: query) }
            let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            guard generation == runsKey else { return }
            records = value; hasMore = value.count == query.limit; error = nil
            cache.runs[cacheKey] = RunsSnapshot(records: value, hasMore: hasMore)
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func loadMore() async {
        guard !loadingRuns else { return }
        let generation = runsKey, paths = model.paths
        loadingRuns = true; defer { if generation == runsKey { loadingRuns = false } }
        let query = GameHistoryQuery(instanceID: instanceID, worldFolder: world?.folder, since: span.since,
                                     search: search, problemsOnly: problemsOnly, limit: 60, offset: records.count)
        do {
            let value = try await Task.detached(priority: .utility) { try GameHistoryStore.list(paths: paths, query: query) }.value
            guard generation == runsKey else { return }
            let known = Set(records.map(\.id))
            records += value.filter { !known.contains($0.id) }
            hasMore = value.count == query.limit
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Header pieces

private struct HeroStatExpandedKey: EnvironmentKey { static let defaultValue = true }
private extension EnvironmentValues {
    var heroStatExpanded: Bool {
        get { self[HeroStatExpandedKey.self] }
        set { self[HeroStatExpandedKey.self] = newValue }
    }
}

/// One fact in the header strip: a label, a rounded number and a line under it.
private struct HeroStat<Detail: View>: View {
    @Environment(\.heroStatExpanded) private var expanded
    let label: String
    let value: String
    @ViewBuilder var detail: Detail
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            detail.font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(height: 20, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .frame(minWidth: 150, maxWidth: expanded ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The last seven days as dots, lit on the days that were played.
private struct WeekDots: View {
    let played: Set<Date>
    private var days: [(date: Date, symbol: String, played: Bool)] {
        var calendar = Calendar.current
        calendar.locale = LocalizationContext.current.formatLocale
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let symbols = calendar.veryShortWeekdaySymbols
            let index = calendar.component(.weekday, from: day) - 1
            return (day, symbols.indices.contains(index) ? symbols[index] : "", played.contains(day))
        }
    }
    var body: some View {
        HStack(spacing: 7) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 3) {
                    Circle().fill(day.played ? AnyShapeStyle(Theme.accent.gradient) : AnyShapeStyle(.primary.opacity(0.12)))
                        .frame(width: 7, height: 7)
                    Text(day.symbol).font(.system(size: 8, weight: .medium)).foregroundStyle(day.played ? .secondary : .tertiary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Messages.HistoryUI.recentWeek.localized)
        .accessibilityValue(Messages.HistoryUI.dayCount(Int64(days.filter(\.played).count)).localized)
    }
}

private struct FilterChip: View {
    let text: String
    let remove: () -> Void
    var body: some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(text).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.accent.opacity(0.12), in: Capsule())
            .foregroundStyle(Theme.accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Messages.HistoryUI.removeFilter.localized)
        .accessibilityLabel(text)
        .accessibilityHint(Messages.HistoryUI.removeFilter.localized)
    }
}

// MARK: - Cards and tiles

/// A save's own `icon.png`, pixel-crisp like the game shows it, or a globe.
private struct WorldIcon: View {
    let image: NSImage?
    var size: CGFloat = 40
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.none).scaledToFill()
            } else {
                Image(systemName: "globe.asia.australia.fill")
                    .font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.teal.gradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// One thing worth remembering: its icon, a kicker, and the name or number.
private struct HighlightCard<Icon: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let kicker: String
    let title: String
    let detail: String
    let help: String
    let action: () -> Void
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: action) {
            HStack(spacing: 16) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    Text(kicker).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Text(title).font(.system(size: 19, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background {
            shape.fill(Theme.surface(for: colorScheme))
                .overlay { shape.fill(.primary.opacity(hovering ? 0.045 : 0)) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, y: 3)
        }
        .overlay {
            shape.strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : colorScheme == .dark ? 0.14 : 0.1), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(kicker + " · " + title)
        .accessibilityValue(detail)
    }
}

/// A grouped total as a tile: icon, name, time and a share bar. The tile is
/// the filter control for that group and shows when it is the one selected.
private struct RankTile<Icon: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let total: GameHistoryTotal
    let share: Double
    let subtitle: String?
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var icon: Icon
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(total.title).font(.headline).lineLimit(1)
                        Text(subtitle ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedFormat.duration(total.seconds))
                            .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                        Spacer(minLength: 6)
                        Text(Messages.HistoryUI.sessionCount(Int64(total.count)).localized + " · " + Messages.HistoryUI.shareOfRange(LocalizedFormat.percent(share)).localized)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.08))
                        GeometryReader { geometry in
                            Capsule().fill(Theme.accent.gradient)
                                .frame(width: max(3, geometry.size.width * min(1, max(0, share))))
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background {
            shape.fill(Theme.surface(for: colorScheme))
                .overlay { shape.fill(selected ? Theme.accent.opacity(0.1) : .primary.opacity(hovering ? 0.045 : 0)) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.04), radius: 8, y: 3)
        }
        .overlay {
            shape.strokeBorder(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary.opacity(colorScheme == .dark ? 0.14 : 0.1)),
                               lineWidth: selected ? 1.5 : 1)
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .help(Messages.HistoryUI.showRuns.localized)
        .accessibilityLabel(total.title)
        .accessibilityValue(LocalizedFormat.duration(total.seconds))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Timeline pieces

/// A day's runs on a 24-hour track, in the manner of the hourly bar in
/// Screen Time. Runs that cross midnight are cut at the day's edges.
private struct DayTrack: View {
    let day: Date
    let records: [GameSession]

    private var segments: [(id: UUID, start: Double, end: Double)] {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { return [] }
        let length = next.timeIntervalSince(day), now = Date()
        return records.compactMap { record in
            let start = max(record.startDate, day)
            let finish = record.endDate ?? (record.state.isFinished ? record.startDate.addingTimeInterval(record.playedSeconds) : now)
            let end = min(max(finish, start), next)
            guard start < next else { return nil }
            return (record.id, start.timeIntervalSince(day) / length, end.timeIntervalSince(day) / length)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.07))
                    ForEach([6, 12, 18], id: \.self) { hour in
                        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 6)
                            .offset(x: geometry.size.width * CGFloat(hour) / 24)
                    }
                    ForEach(segments, id: \.id) { segment in
                        Capsule().fill(Theme.accent.gradient)
                            .frame(width: max(3, geometry.size.width * (segment.end - segment.start)))
                            .offset(x: geometry.size.width * segment.start)
                    }
                }
            }
            .frame(height: 6)
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    if hour > 0 { Spacer(minLength: 0) }
                    Text(LocalizedFormat.number(hour)).font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Messages.HistoryUI.dayTrack.localized)
    }
}

/// One run in the timeline: when it started, where, and how it ended.
private struct HistoryRunRow: View {
    let record: GameSession
    let instance: GameInstance?
    let worldIcon: NSImage?
    let action: () -> Void
    @State private var hovering = false

    private var time: String {
        let start = LocalizedFormat.date(record.startDate, date: .omitted, time: .shortened)
        guard let end = record.endDate, end > record.startDate else { return start }
        return Messages.HistoryUI.timeRange(start, LocalizedFormat.date(end, date: .omitted, time: .shortened)).localized
    }
    /// Only an unusual ending earns a glyph; a normal run reads clean.
    private var showsResult: Bool { record.needsAttention || !record.state.isFinished || record.hasPostCommandFailure }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let instance { InstanceIcon(instance, size: 36) }
                else { InstanceIcon(loader: LoaderKind(rawValue: record.loader) ?? .vanilla, size: 36) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(record.instanceName).font(.subheadline.weight(.medium)).lineLimit(1)
                        if instance == nil {
                            Text(Messages.HistoryUI.instanceRemoved.localized).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(time).monospacedDigit()
                        if let world = record.world {
                            Text("·")
                            HStack(spacing: 4) {
                                if let worldIcon {
                                    Image(nsImage: worldIcon).resizable().interpolation(.none).scaledToFill()
                                        .frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3))
                                        .accessibilityHidden(true)
                                } else {
                                    Image(systemName: "map").font(.caption2)
                                }
                                Text(world.name).lineLimit(1)
                            }
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
                if showsResult {
                    Label(record.userResult, systemImage: record.resultSymbol)
                        .labelStyle(.titleAndIcon).font(.caption)
                        .foregroundStyle(record.resultColor)
                        .lineLimit(1)
                }
                Text(record.userDuration).font(.callout.weight(.medium)).monospacedDigit().lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(hovering ? 0.045 : 0))
        .onHover { hovering = $0 }
        .accessibilityLabel(record.instanceName)
        .accessibilityValue(record.userResult + " · " + record.userDuration)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
