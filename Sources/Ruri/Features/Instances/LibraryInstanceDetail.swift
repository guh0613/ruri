import RuriLocalization
import SwiftUI
import AppKit
import Charts
import RuriCore

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
    @State private var content: [ContentKind: (total: Int, disabled: Int)] = [:]
    @State private var worlds: [WorldSnapshot] = []
    @State private var worldIcons: [String: NSImage] = [:]
    @State private var backups = 0
    @State private var loaded = false
    /// Counts are read again when a content or save manager closes.
    private var managerOpen: Bool { model.contentInstance != nil || model.worldInstance != nil }
    private var sessions: [GameSession] { model.sessions.filter { $0.instanceID == instance.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 32) {
                    notices
                    strip
                    worldsSection
                    historySection
                }
                .padding(.horizontal, 28).padding(.bottom, 32)
                .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .softTopScrollEdge()
        .task(id: managerOpen) { if !managerOpen { await load() } }
    }

    // MARK: Header

    private var hero: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) { identity; Spacer(minLength: 16); actions }
            VStack(alignment: .leading, spacing: 18) { identity; actions }
        }
        .padding(.horizontal, 28).padding(.top, 64).padding(.bottom, 28)
        .frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
        // Reach up under the toolbar so the wash continues behind it instead
        // of starting at the content edge.
        .background { backdrop.padding(.top, -160).clipped().accessibilityHidden(true) }
    }

    /// A soft wash of the instance's own icon, or of the accent colour with
    /// its loader mark when it has none, fading into the page.
    private var backdrop: some View {
        let canvas = Theme.canvas(for: colorScheme)
        return ZStack {
            canvas
            if let png = instance.iconPNG, let image = InstanceIconCache.image(png) {
                Image(nsImage: image).resizable().scaledToFill()
                    .blur(radius: 60, opaque: true).saturation(1.4)
                    .opacity(colorScheme == .dark ? 0.55 : 0.4)
            } else {
                LinearGradient(colors: [Theme.accent.opacity(colorScheme == .dark ? 0.28 : 0.16), Theme.accent.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                LoaderGlyph.image(for: instance.loader.modrinthLoader).resizable().scaledToFit()
                    .frame(width: 240, height: 240)
                    .foregroundStyle(Theme.accent.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    .rotationEffect(.degrees(-12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .offset(x: -48, y: -36)
            }
            LinearGradient(colors: [canvas.opacity(0), canvas], startPoint: UnitPoint(x: 0.5, y: 0.3), endPoint: .bottom)
        }
    }

    private var identity: some View {
        HStack(alignment: .bottom, spacing: 20) {
            Button { model.editingInstance = instance } label: {
                InstanceIcon(loader: instance.loader, size: 108, png: instance.iconPNG)
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
            .help(Messages.AppLibraryView.changeIconOrEditSettings.localized)
            .accessibilityLabel(Messages.AppLibraryView.editIconAndSettings(instance.name).localized)
            VStack(alignment: .leading, spacing: 8) {
                Text(instance.name).font(.system(size: 30, weight: .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                InstanceMetadata(instance: instance)
                InstanceStatus(instance: instance)
                if let issue = instance.repositoryIssue { Text(issue).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(issue) }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
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

    private var stripItems: [StripItem] {
        var items = [
            StripItem(id: "playTime", label: Messages.AppHomeView.playTime.localized, value: instance.playTimeLabel,
                      detail: sessions.isEmpty ? nil : Messages.AppLibraryView.runCount(Int64(sessions.count)).localized),
            StripItem(id: "lastPlayed", label: Messages.AppHomeView.lastPlayed.localized, value: instance.lastPlayed.map(LocalizedFormat.relative) ?? Messages.AppHomeView.neverPlayed.localized,
                      detail: instance.lastPlayed.map { LocalizedFormat.date($0, time: .omitted) }),
        ]
        for kind in ContentKind.allCases where instance.loader != .vanilla || kind == .resourcepack {
            let tally = content[kind]
            items.append(StripItem(id: kind.rawValue, label: kind.title, value: tally.map { LocalizedFormat.number($0.total) } ?? (loaded ? "—" : "…"),
                                   detail: tally.flatMap { $0.disabled > 0 ? Messages.AppLibraryView.disabledCount(Int64($0.disabled)).localized : nil }) {
                model.contentKind = kind; model.contentInstance = instance
            })
        }
        if let memory = try? instance.resolvedLaunchSettings(defaults: model.state.settings).memoryPreview() {
            items.append(StripItem(id: "memory", label: Messages.AppHomeView.memory.localized, value: LaunchMemory.size(memory.maximumBytes), detail: memory.maximumSource.title))
        } else {
            items.append(StripItem(id: "memory", label: Messages.AppHomeView.memory.localized, value: Messages.AppInstancePresentation.memoryNeedsCheck.localized))
        }
        return items
    }

    /// One row of equal columns split by hairlines, like the facts under an
    /// App Store title; it scrolls sideways when the page is too narrow.
    private var strip: some View {
        let items = stripItems
        return ViewThatFits(in: .horizontal) {
            stripRow(items, expanded: true)
            ScrollView(.horizontal, showsIndicators: false) { stripRow(items, expanded: false) }
        }
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
    }

    private func stripRow(_ items: [StripItem], expanded: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().frame(height: 36) }
                StripCell(item: item).frame(minWidth: 104, maxWidth: expanded ? .infinity : nil)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: Worlds

    private var worldsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppLibraryView.worlds.localized) {
                HStack(spacing: 14) {
                    if backups > 0 { Text(Messages.AppLibraryView.backupCount(Int64(backups)).localized).foregroundStyle(.secondary) }
                    link(Messages.AppLibraryView.manage.localized) { model.worldInstance = instance }
                }
            }
            if !loaded {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 68)
            } else if worlds.isEmpty {
                Surface {
                    Label(Messages.AppLibraryView.noWorlds.localized, systemImage: "globe")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: Play history

    private var playDays: [PlayDay] {
        let calendar = Calendar.current, today = calendar.startOfDay(for: .now)
        var minutes: [Date: Double] = [:]
        for session in sessions {
            if let exit = session.exit { minutes[calendar.startOfDay(for: exit.startedAt), default: 0] += exit.playTime / 60 }
        }
        return (0..<14).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { PlayDay(date: $0, minutes: minutes[$0] ?? 0) }
        }
    }

    private var historySection: some View {
        let days = playDays, recent = Array(sessions.prefix(3))
        let total = days.reduce(0) { $0 + $1.minutes }, peak = days.map(\.minutes).max() ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppLibraryView.playHistory.localized) {
                if let latest = sessions.first { link(Messages.AppLibraryView.allRuns.localized) { model.showSession(latest.id) } }
            }
            Surface(padding: 0) {
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
                        Chart(days) { day in
                            BarMark(x: .value(Messages.AppLibraryView.date.localized, day.date, unit: .day),
                                    y: .value(Messages.AppHomeView.playTime.localized, day.minutes))
                                .foregroundStyle(Theme.accent.gradient)
                                .cornerRadius(3)
                        }
                        .chartYScale(domain: 0...max(60, peak))
                        .chartYAxis {
                            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                                AxisGridLine()
                                AxisValueLabel { if let minutes = value.as(Double.self) { Text(LocalizedFormat.duration(minutes * 60)) } }
                            }
                        }
                        .frame(height: 130)
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
            }
        }
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) { Text(title); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
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
        let recent = overview?.recent ?? []
        let icons = await Task.detached(priority: .utility) {
            recent.reduce(into: [String: Data]()) { result, world in
                if let url = world.icon, let data = try? Data(contentsOf: url), data.count <= 1_048_576 { result[world.id] = data }
            }
        }.value
        guard !Task.isCancelled else { return }
        content = counts
        worlds = recent
        backups = overview?.backups ?? 0
        worldIcons = icons.compactMapValues(NSImage.init(data:))
        loaded = true
    }
}

private struct PlayDay: Identifiable {
    let date: Date
    let minutes: Double
    var id: Date { date }
}

private struct StripItem: Identifiable {
    let id: String
    let label: String
    let value: String
    var detail: String?
    var action: (() -> Void)?
}

private struct StripCell: View {
    let item: StripItem
    @State private var hovering = false
    var body: some View {
        if let action = item.action {
            Button(action: action) { cell.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .background(.primary.opacity(hovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
                .onHover { hovering = $0 }
        } else {
            cell
        }
    }
    private var cell: some View {
        VStack(spacing: 4) {
            Text(item.label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Text(item.value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            // Cells that open a manager say so with a link-coloured line, so
            // every cell keeps three lines and none reads as a blank gap.
            if item.action != nil {
                HStack(spacing: 2) {
                    Text(item.detail ?? Messages.AppLibraryView.manage.localized)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                }
                .font(.caption).foregroundStyle(Theme.accent).lineLimit(1)
            } else {
                Text(item.detail ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }
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

private struct RunRow: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    @State private var hovering = false
    var body: some View {
        Button { model.showSession(session.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.state.isFinished ? session.title : model.runningLabel(session.instanceID) ?? session.stage.title)
                        .font(.callout.weight(.medium)).lineLimit(1)
                    Text(LocalizedFormat.date(session.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let exit = session.exit {
                    Text(LocalizedFormat.duration(exit.playTime)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
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
