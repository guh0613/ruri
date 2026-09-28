import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct LibraryInstanceSnapshot {
    struct Key: Hashable {
        let instanceID: UUID
        let gameDirectory: URL
        let dataDirectory: URL
    }

    var content: [ContentKind: (total: Int, disabled: Int)] = [:]
    var worlds: [WorldSnapshot] = []
    var worldIcons: [String: NSImage] = [:]
    var backups = 0
    var servers: [ServerEntry] = []
    var loaded = false
    var sessions: [GameSession] = []
    var historyDays: [GameSessionTiming.Day] = []
    var historyLoaded = false
}

/// The instance chosen in the library, laid out like a game page in the App
/// Store or Games: a header tinted by the instance's artwork with the launch
/// button, a strip of the numbers players check, their worlds, and how play
/// time and recent runs went.
struct LibraryInstanceDetail<Notices: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let instance: GameInstance
    let onTrash: (GameInstance) -> Void
    @ViewBuilder var notices: Notices
    let cache: ViewSnapshotCache<LibraryInstanceSnapshot.Key, LibraryInstanceSnapshot>
    let cacheKey: LibraryInstanceSnapshot.Key
    @State private var snapshot: LibraryInstanceSnapshot
    private var content: [ContentKind: (total: Int, disabled: Int)] { snapshot.content }
    private var worlds: [WorldSnapshot] { snapshot.worlds }
    private var worldIcons: [String: NSImage] { snapshot.worldIcons }
    private var backups: Int { snapshot.backups }
    private var loaded: Bool { snapshot.loaded }
    private var sessions: [GameSession] { snapshot.sessions }
    private var historyDays: [GameSessionTiming.Day] { snapshot.historyDays }
    /// Counts are read again when a content, save or server manager closes.
    private var managerOpen: Bool { model.contentPresentation != nil || model.worldInstance != nil || model.serverInstance != nil }

    init(instance: GameInstance, cache: ViewSnapshotCache<LibraryInstanceSnapshot.Key, LibraryInstanceSnapshot>,
         cacheKey: LibraryInstanceSnapshot.Key, onTrash: @escaping (GameInstance) -> Void,
         @ViewBuilder notices: () -> Notices) {
        self.instance = instance
        self.cache = cache
        self.cacheKey = cacheKey
        self.onTrash = onTrash
        self.notices = notices()
        _snapshot = State(initialValue: cache[cacheKey] ?? LibraryInstanceSnapshot())
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(topInset: geometry.safeAreaInsets.top)
                    VStack(alignment: .leading, spacing: 32) {
                        notices
                        FactStrip(items: stripItems)
                        worldsSection
                        serversSection
                        historySection
                    }
                    .padding(.horizontal, 28).padding(.bottom, 32)
                    .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .softTopScrollEdge()
        }
        .task(id: managerOpen) { if !managerOpen { await load() } }
        .task(id: "\(instance.id)-\(model.historyRevision)") {
            let paths = model.paths, id = instance.id
            let since = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: Date())) ?? Date()
            let result = await Task.detached(priority: .utility) {
                try? (GameHistoryStore.list(paths: paths, query: .init(instanceID: id, limit: 3)), GameHistoryStore.days(paths: paths, instanceID: id, since: since))
            }.value
            guard !Task.isCancelled else { return }
            if let result { snapshot.sessions = result.0; snapshot.historyDays = result.1 }
            else if !snapshot.historyLoaded { snapshot.sessions = Array(model.sessions.filter { $0.instanceID == id }.prefix(3)) }
            snapshot.historyLoaded = true
            cache[cacheKey] = snapshot
        }
    }

    // MARK: Header

    private func hero(topInset: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) { identity; Spacer(minLength: 16); actions }
            VStack(alignment: .leading, spacing: 18) { identity; actions }
        }
        .padding(.horizontal, 28).padding(.top, 64 + topInset).padding(.bottom, 28)
        .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
        // The scroll view extends into the title bar; only the controls need
        // its safe-area inset, so the artwork fills the entire header.
        .background { backdrop.clipped().accessibilityHidden(true) }
    }

    /// A soft wash of the instance's icon, custom or built-in, fading into the page.
    private var backdrop: some View {
        let canvas = Theme.canvas(for: colorScheme)
        return ZStack {
            canvas
            Group {
                if let png = instance.iconPNG, let image = InstanceIconCache.image(png) {
                    Image(nsImage: image).resizable()
                } else if let tile = InstanceIconCache.tile(instance.iconStyle ?? .standard(for: instance.loader), pixels: 128) {
                    Image(decorative: tile, scale: 1).resizable()
                }
            }
            .scaledToFill()
            .blur(radius: 60, opaque: true).saturation(1.4)
            .opacity(colorScheme == .dark ? 0.55 : 0.4)
            LinearGradient(colors: [canvas.opacity(0), canvas], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
        }
    }

    private var identity: some View {
        HStack(alignment: .instanceIdentityCenter, spacing: 20) {
            Button { model.editingInstance = instance } label: {
                InstanceIcon(instance, size: 108)
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            .help(Messages.AppLibraryView.changeIconOrEditSettings.localized)
            .accessibilityLabel(Messages.AppLibraryView.editIconAndSettings(instance.name).localized)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(instance.name).font(.system(size: 30, weight: .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    InstanceMetadata(instance: instance)
                }
                // Anchor the title and metadata; reserve a status line below them.
                .alignmentGuide(.instanceIdentityCenter) { $0[VerticalAlignment.center] }
                InstanceStatus(instance: instance, reservesSpace: true)
                if let issue = instance.repositoryIssue { Text(issue).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(issue) }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            PinToggleButton(pinned: instance.favorite) { model.setFavorite(!instance.favorite, for: instance) }.disabled(model.readOnly)
            circleAction("slider.horizontal.3", Messages.AppLibraryView.instanceSettings.localized) { model.editingInstance = instance }
            circleAction("folder", Messages.AppLibraryView.showInFinder.localized) { model.reveal(instance) }
            InstanceMenu(instance: instance, onTrash: onTrash) { Image(systemName: "ellipsis.circle").font(.title2) }
            LaunchButton(instance: instance, size: .large)
        }
        .fixedSize()
    }

    private func circleAction(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 18) }
            .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large)
            .help(title).accessibilityLabel(title)
    }

    // MARK: Numbers

    private var stripItems: [FactStripItem] {
        var items = [
            FactStripItem(id: "playTime", label: Messages.AppHomeView.playTime.localized, value: instance.playTimeLabel,
                      detail: sessions.isEmpty ? nil : Messages.AppLibraryView.runCount(Int64(sessions.count)).localized),
            FactStripItem(id: "lastPlayed", label: Messages.AppHomeView.lastPlayed.localized, value: instance.lastPlayed.map(LocalizedFormat.relative) ?? Messages.AppHomeView.neverPlayed.localized,
                      detail: instance.lastPlayed.map { LocalizedFormat.date($0, time: .omitted) }),
        ]
        for kind in ContentKind.allCases where instance.loader != .vanilla || kind == .resourcepack {
            let tally = content[kind]
            items.append(FactStripItem(id: kind.rawValue, label: kind.title, value: tally.map { LocalizedFormat.number($0.total) } ?? (loaded ? "—" : "…"),
                                   detail: tally.flatMap { $0.disabled > 0 ? Messages.AppLibraryView.disabledCount(Int64($0.disabled)).localized : nil }) {
                model.contentPresentation = .init(instance: instance, kind: kind)
            })
        }
        if let memory = try? instance.resolvedLaunchSettings(defaults: model.state.settings).memoryPreview(workload: MemoryWorkload.cached(paths: model.paths, instance: instance)) {
            items.append(FactStripItem(id: "memory", label: Messages.AppHomeView.memory.localized, value: LaunchMemory.size(memory.maximumBytes), detail: memory.maximumSource.title))
        } else {
            items.append(FactStripItem(id: "memory", label: Messages.AppHomeView.memory.localized, value: Messages.AppInstancePresentation.memoryNeedsCheck.localized))
        }
        return items
    }

    // MARK: Worlds

    private var worldsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppLibraryView.worlds.localized) {
                HStack(spacing: 14) {
                    if backups > 0 { Text(Messages.AppLibraryView.backupCount(Int64(backups)).localized).foregroundStyle(.secondary) }
                    SectionLink(Messages.AppLibraryView.manage.localized) { model.worldInstance = instance }
                }
            }
            if !loaded {
                DelayedProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 68)
            } else if worlds.isEmpty {
                Surface(padding: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "globe").font(.system(size: 28))
                            .foregroundStyle(.tertiary).accessibilityHidden(true)
                        VStack(spacing: 4) {
                            Text(Messages.AppLibraryView.noWorlds.localized).font(.headline)
                            Text(Messages.AppWorldManagerView.worldDescription.localized).font(.callout)
                        }.foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(worlds) { world in
                        WorldTile(world: world, icon: worldIcons[world.id]) { model.worldInstance = instance }
                    }
                }
            }
        }
    }

    // MARK: Servers

    /// The instance's multiplayer list in game order; a tile opens the server
    /// in the server center, where it can be joined or inspected.
    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.Servers.page.localized) {
                HStack(spacing: 14) {
                    if snapshot.servers.count > 6 { Text(Messages.Servers.serverCount(Int64(snapshot.servers.count)).localized).foregroundStyle(.secondary) }
                    SectionLink(Messages.Servers.manageList.localized) { model.serverInstance = instance }
                }
            }
            if !loaded {
                DelayedProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 68)
            } else if snapshot.servers.isEmpty {
                Surface(padding: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "server.rack").font(.system(size: 26))
                            .foregroundStyle(.tertiary).accessibilityHidden(true)
                        VStack(spacing: 4) {
                            Text(Messages.Servers.emptyInstanceList.localized).font(.headline)
                            Text(Messages.Servers.emptyInstanceListDescription.localized).font(.callout)
                        }.foregroundStyle(.secondary)
                        Button(Messages.Servers.add.localized) { model.serverInstance = instance }
                            .disabled(model.readOnly)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(snapshot.servers.prefix(6)) { entry in
                        ServerTile(entry: entry) {
                            if let address = entry.endpoint { model.showServer(address) } else { model.serverInstance = instance }
                        }
                    }
                }
            }
        }
    }

    // MARK: Play history

    private var playDays: [InstancePlaytimeChart.Day] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: .now)
        var minutes: [Date: Double] = [:]
        for day in historyDays { minutes[calendar.startOfDay(for: day.date), default: 0] += day.seconds / 60 }
        return (0..<14).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { InstancePlaytimeChart.Day(date: $0, minutes: minutes[$0] ?? 0) }
        }
    }

    private var historySection: some View {
        let days = playDays, recent = Array(sessions.prefix(3))
        let total = days.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppLibraryView.playHistory.localized) {
                SectionLink(Messages.SessionUI.history.localized) { model.showHistory(instanceID: instance.id) }
            }
            Surface(padding: 0) {
                if snapshot.historyLoaded {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Messages.AppLibraryView.lastTwoWeeks.localized).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                if total > 0 {
                                    Text(LocalizedFormat.duration(total * 60)).font(.system(size: 22, weight: .semibold, design: .rounded))
                                } else {
                                    Text(Messages.AppLibraryView.noRecentPlay.localized).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            InstancePlaytimeChart(days: days).frame(height: 130)
                        }
                        .padding(20)
                        Divider()
                        if recent.isEmpty {
                            Text(Messages.AppLibraryView.noRuns.localized).font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        } else {
                            ForEach(recent) { run in
                                RunRow(session: run)
                                if run.id != recent.last?.id { Divider().padding(.leading, 50) }
                            }
                        }
                    }
                } else {
                    DelayedProgressView().frame(maxWidth: .infinity, minHeight: 254)
                }
            }
        }
    }

    // MARK: Loading

    private func load() async {
        let paths = model.paths, id = instance.id
        let manager = ContentManager(paths: paths, instanceID: id)
        var counts: [ContentKind: (total: Int, disabled: Int)] = [:]
        for kind in ContentKind.allCases {
            if let tally = try? await manager.count(kind) { counts[kind] = tally }
        }
        let overview = try? await WorldManager(paths: paths, instanceID: id).overview(limit: 6)
        let servers = await Task.detached(priority: .utility) { try? ServerListManager(paths: paths, instanceID: id).snapshot().entries }.value
        let recent = overview?.recent ?? []
        let icons = await Task.detached(priority: .utility) {
            recent.reduce(into: [String: Data]()) { result, world in
                if let url = world.icon, let data = try? Data(contentsOf: url), data.count <= 1_048_576 { result[world.id] = data }
            }
        }.value
        guard !Task.isCancelled else { return }
        // Keep the last successful values if a background refresh cannot read a folder.
        snapshot.content.merge(counts) { _, new in new }
        if let overview {
            snapshot.worlds = recent
            snapshot.backups = overview.backups
            snapshot.worldIcons = icons.compactMapValues(NSImage.init(data:))
        }
        if let servers { snapshot.servers = servers }
        snapshot.loaded = true
        cache[cacheKey] = snapshot
    }
}

private extension VerticalAlignment {
    enum InstanceIdentityCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    static let instanceIdentityCenter = VerticalAlignment(InstanceIdentityCenter.self)
}

private struct WorldTile: View {
    let world: WorldSnapshot
    let icon: NSImage?
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Surface(padding: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Group {
                        if let icon {
                            Image(nsImage: icon).resizable().interpolation(.none)
                        } else {
                            Image(systemName: "globe.americas.fill").font(.system(size: 20)).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.accent.opacity(0.12))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(world.name).font(.headline).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(hovering ? 0.045 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering = $0 }
        .help(world.name)
    }
    private var subtitle: String {
        [world.gameMode, world.version, world.lastPlayed.map(LocalizedFormat.relative)].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ServerTile: View {
    let entry: ServerEntry
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Surface(padding: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    ServerIcon(data: entry.icon, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name.isEmpty ? entry.address : entry.name).font(.headline).lineLimit(1)
                        Text(entry.endpoint?.authority ?? entry.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(hovering ? 0.045 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering = $0 }
        .help(Messages.Servers.showInServers.localized)
    }
}

private struct RunRow: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    @State private var hovering = false
    var body: some View {
        Button { model.inspectSession(session) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.userResult)
                        .font(.callout.weight(.medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(LocalizedFormat.date(session.createdAt))
                        if session.activity != nil || session.world != nil {
                            Text("·")
                            Label(session.activityDescription, systemImage: "gamecontroller").labelStyle(.titleAndIcon).lineLimit(1)
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if session.hasPlayed { Text(session.userDuration).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.primary.opacity(hovering ? 0.045 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
    private var symbol: String {
        switch session.state {
        case .preparing, .running: "play.circle.fill"
        case .succeeded: "checkmark.circle"
        case .stopped, .cancelled: "stop.circle"
        case .failed: "xmark.octagon"
        case .interrupted: "exclamationmark.triangle"
        }
    }
    private var tint: Color {
        switch session.state {
        case .preparing, .running: Theme.accent
        case .failed: .red
        case .interrupted: .orange
        case .succeeded, .stopped, .cancelled: .secondary
        }
    }
}
