import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// The landing page: the instance to play next, what is running or
/// installing right now, the other instances played recently, and shortcuts
/// to the things a new player does first.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    private var featured: GameInstance? { model.selected }
    private var recent: [GameInstance] {
        Array(model.directoryInstances.filter { $0.id != featured?.id }
            .sorted { ($0.lastPlayed ?? .distantPast, $0.createdAt) > ($1.lastPlayed ?? .distantPast, $1.createdAt) }
            .prefix(8))
    }
    private var running: [GameSession] { model.activeSessions.values.filter { !$0.state.isFinished }.sorted { $0.createdAt < $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                if model.directoryInstances.isEmpty {
                    emptyState
                } else {
                    if let featured { featuredSection(featured) }
                    if !running.isEmpty { runningSection }
                    if let task = model.activeActivity { activitySection(task) }
                    if !recent.isEmpty { recentSection }
                }
                quickActions
            }
            .padding(.horizontal, 40).padding(.vertical, 32).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Messages.AppHomeView.emptyStateText1.localized, systemImage: "square.grid.2x2")
        } description: {
            Text(Messages.AppHomeView.emptyStateText2.localized)
        } actions: {
            Button(Messages.AppHomeView.emptyStateText3.localized) { model.showCreate = true }.buttonStyle(.borderedProminent)
            Button(Messages.AppHomeView.emptyStateText4.localized) { model.chooseInstanceImport() }
        }
        .disabled(model.busy)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: Continue playing

    private func featuredSection(_ instance: GameInstance) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.featuredSectionText1.localized) { seeAll(Messages.AppHomeView.featuredSectionText2.localized) { model.page = .library } }
            Surface(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) {
                            featuredIdentity(instance)
                            Spacer(minLength: 24)
                            featuredActions(instance)
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 18) {
                            featuredIdentity(instance)
                            HStack { Spacer(); featuredActions(instance) }
                        }
                    }
                    .padding(24)
                    Divider()
                    HStack(spacing: 16) {
                        StatTile(label: Messages.AppHomeView.featuredSectionText4.localized, value: instance.playTimeLabel)
                        Divider().frame(height: 28)
                        StatTile(label: Messages.AppHomeView.featuredSectionText5.localized, value: instance.lastPlayed.map(LocalizedFormat.relative) ?? Messages.AppHomeView.featuredSectionText6.localized)
                        Divider().frame(height: 28)
                        StatTile(label: Messages.AppHomeView.featuredSectionText7.localized, value: "\(instance.gameVersion) · \(instance.loaderLabel)")
                        Divider().frame(height: 28)
                        StatTile(label: Messages.AppHomeView.featuredSectionText8.localized, value: model.memoryLabel(instance))
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    if model.activeAccount == nil {
                        Divider()
                        HStack {
                            Label(Messages.AppHomeView.featuredSectionText9.localized, systemImage: "person.crop.circle.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button(Messages.AppHomeView.featuredSectionText10.localized) { model.showAccount = true }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private func featuredIdentity(_ instance: GameInstance) -> some View {
        HStack(spacing: 20) {
            Button { model.editingInstance = instance } label: {
                InstanceIcon(loader: instance.loader, size: 84, png: instance.iconPNG)
            }.buttonStyle(.plain).help(Messages.AppHomeView.featuredSectionText3.localized)
            VStack(alignment: .leading, spacing: 6) {
                Text(instance.name).font(.title2.weight(.semibold)).lineLimit(2)
                Text(instance.subtitle).foregroundStyle(.secondary).lineLimit(2)
                statusLine(instance).font(.callout).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featuredActions(_ instance: GameInstance) -> some View {
        HStack(spacing: 12) {
            InstanceQuickActions(instance: instance).controlSize(.large)
            LaunchButton(instance: instance, size: .large)
            InstanceMenu(instance: instance, showsSelect: false) { Image(systemName: "ellipsis.circle").font(.title3) }
        }.fixedSize()
    }

    private func statusLine(_ instance: GameInstance) -> some View {
        HStack(spacing: 6) {
            Circle().fill(model.statusColor(instance)).frame(width: 7, height: 7)
            Text(model.runningLabel(instance.id) ?? (instance.installed ? Messages.AppHomeView.statusLineText1.localized : Messages.AppHomeView.statusLineText2.localized))
            if let issue = instance.repositoryIssue { Text("·").foregroundStyle(.tertiary); Text(issue).lineLimit(1).help(issue) }
        }
    }

    // MARK: Running and active work

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.runningSectionText1.localized)
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(running) { record in
                        HStack(spacing: 14) {
                            let instance = model.state.instances.first { $0.id == record.instanceID }
                            InstanceIcon(loader: instance?.loader ?? .vanilla, size: 40, png: instance?.iconPNG)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.instanceName).font(.headline).lineLimit(1)
                                Text(model.runningLabel(record.instanceID) ?? record.stage.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(Messages.AppHomeView.instanceText1.localized) { model.showSession(record.id) }
                            if record.gameIdentity?.isAlive == true { Button(Messages.AppHomeView.instanceText2.localized) { model.returnToGame(record.instanceID) }.buttonStyle(.borderedProminent) }
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if record.id != running.last?.id { Divider().padding(.leading, 70) }
                    }
                }
            }
        }
    }

    private func activitySection(_ task: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.activitySectionText1.localized) { seeAll(Messages.AppHomeView.activitySectionText2.localized) { model.page = .downloads } }
            Surface {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(task.title).font(.headline).lineLimit(1); Spacer(); Button(Messages.Common.cancel.localized) { model.operation?.cancel() }.controlSize(.small) }
                    if task.progress.total > 0 { ProgressView(value: task.progress.fraction) } else { ProgressView().controlSize(.small) }
                    HStack { Text(task.progress.stage).lineLimit(1); Spacer(); if task.progress.total > 0 { Text("\(task.progress.completed) / \(task.progress.total)").monospacedDigit() } }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Recently played

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.recentSectionText1.localized)
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(recent) { instance in
                        recentRow(instance)
                        if instance.id != recent.last?.id { Divider().padding(.leading, 70) }
                    }
                }
            }
        }
    }

    private func recentRow(_ instance: GameInstance) -> some View {
        HStack(spacing: 14) {
            InstanceIcon(loader: instance.loader, size: 40, png: instance.iconPNG)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name).font(.headline).lineLimit(1)
                Text(instance.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(model.runningLabel(instance.id) ?? instance.lastPlayedLabel).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            LaunchButton(instance: instance, compact: true)
            InstanceMenu(instance: instance)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { model.select(instance) }
        .help(Messages.AppHomeView.recentRowText1.localized)
        .contextMenu {
            Button(Messages.AppHomeView.recentRowText2.localized) { model.select(instance) }
            Button(Messages.AppHomeView.recentRowText3.localized, systemImage: "slider.horizontal.3") { model.editingInstance = instance }
            Button(Messages.AppHomeView.recentRowText4.localized, systemImage: "folder") { model.reveal(instance) }
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.quickActionsText1.localized)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)], spacing: 14) {
                ActionTile(symbol: "plus.square", title: Messages.AppHomeView.emptyStateText3.localized, detail: Messages.AppHomeView.quickActionsText2.localized) { model.showCreate = true }
                ActionTile(symbol: "square.and.arrow.down", title: Messages.AppHomeView.quickActionsText3.localized, detail: Messages.AppHomeView.quickActionsText4.localized) { model.chooseInstanceImport() }
                ActionTile(symbol: "safari", title: Messages.AppHomeView.quickActionsText5.localized, detail: Messages.AppHomeView.quickActionsText6.localized) { model.page = .discover }
                if model.activeAccount == nil {
                    ActionTile(symbol: "person.crop.circle.badge.plus", title: Messages.AppHomeView.featuredSectionText10.localized, detail: Messages.AppHomeView.quickActionsText7.localized) { model.showAccount = true }
                } else {
                    ActionTile(symbol: "cup.and.saucer", title: Messages.AppHomeView.quickActionsText8.localized, detail: Messages.AppHomeView.quickActionsText9.localized) { model.page = .java }
                }
            }
            .disabled(model.busy)
        }
    }

    private func seeAll(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) { Text(title); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
    }
}
