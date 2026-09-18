import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

/// The landing page: the instance to play next, what is running or
/// installing right now, the other instances played recently, and shortcuts
/// to the things a new player does first.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    private var featured: GameInstance? { model.selected }
    private var recent: [GameInstance] {
        Array(model.directoryInstances.filter { $0.id != featured?.id }
            .sorted { ($0.lastPlayed ?? .distantPast, $0.createdAt) > ($1.lastPlayed ?? .distantPast, $1.createdAt) }
            .prefix(8))
    }
    private var running: [GameSession] { model.activeSessions.values.filter { !$0.state.isFinished }.sorted { $0.createdAt < $1.createdAt } }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if model.directoryInstances.isEmpty {
                        emptyState
                    } else if let featured {
                        featuredSection(featured)
                    }
                    if !running.isEmpty { runningSection }
                    if let task = model.activeActivity { activitySection(task) }
                    HomeActivityCard()
                    if !recent.isEmpty { recentSection }
                    quickActions(columns: geometry.size.width >= 1000 ? 4 : geometry.size.width >= 620 ? 2 : 1)
                }
                .padding(28)
                .frame(maxWidth: 1380, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(Theme.canvas(for: colorScheme))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Messages.AppHomeView.noInstances.localized, systemImage: "square.grid.2x2")
        } description: {
            Text(Messages.AppHomeView.emptyStateDescription.localized)
        } actions: {
            VStack(spacing: 24) {
                HStack(spacing: 12) {
                    Button(Messages.AppHomeView.createInstance.localized) { model.showCreate = true }.buttonStyle(.borderedProminent)
                    Button(Messages.AppHomeView.importPack.localized) { model.chooseInstanceImport() }.buttonStyle(.bordered)
                }.fixedSize()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { existingFolderActions }.fixedSize()
                    VStack(spacing: 8) { existingFolderActions }
                }.font(.callout)
            }
        }
        .disabled(model.busy)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    @ViewBuilder private var existingFolderActions: some View {
        Text(Messages.AppHomeView.existingGameFolderHint.localized).foregroundStyle(.secondary)
        Button(Messages.AppHomeView.addExistingGameFolder.localized, systemImage: "folder.badge.plus") { model.chooseMinecraftDirectory() }
            .buttonStyle(.link).disabled(model.readOnly)
            .help(Messages.AppAppModelMinecraftDirectory.folderSelectionHelp.localized)
    }

    // MARK: Continue playing

    private func featuredSection(_ instance: GameInstance) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.continuePlaying.localized) { seeAll(Messages.AppHomeView.allInstances.localized) { model.page = .library } }
            Surface(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HomeFeaturedHeaderLayout {
                        featuredIdentity(instance)
                        LaunchButton(instance: instance, size: .large)
                        featuredActions(instance)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 22)
                    Divider()
                    featuredStats(instance)
                        .padding(.horizontal, 24).padding(.vertical, 18)
                    if model.activeAccount == nil {
                        Divider()
                        HStack {
                            Label(Messages.AppHomeView.noAccountNotice.localized, systemImage: "person.crop.circle.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button(Messages.AppHomeView.addAccount.localized) { model.showAccount = true }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private func featuredIdentity(_ instance: GameInstance) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Button { model.editingInstance = instance } label: {
                InstanceIcon(instance, size: 80)
            }.buttonStyle(.plain).help(Messages.AppHomeView.editInstance.localized)
                .accessibilityLabel(Messages.AppLibraryView.editIconAndSettings(instance.name).localized)
            VStack(alignment: .leading, spacing: 10) {
                Text(instance.name).font(.system(size: 24, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                InstanceMetadata(instance: instance)
                InstanceStatus(instance: instance)
                if let issue = instance.repositoryIssue {
                    Text(issue).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(issue)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func featuredActions(_ instance: GameInstance) -> some View {
        HStack(spacing: 12) {
            InstanceQuickActions(instance: instance)
            InstanceMenu(instance: instance, showsSelect: false) { Image(systemName: "ellipsis.circle").font(.title3) }
        }.fixedSize()
    }

    private func featuredStats(_ instance: GameInstance) -> some View {
        HStack(alignment: .top, spacing: 20) {
            StatTile(label: Messages.AppHomeView.playTime.localized, value: instance.playTimeLabel)
                .frame(minWidth: 80, maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            Divider().frame(height: 32)
            StatTile(label: Messages.AppHomeView.lastPlayed.localized, value: instance.lastPlayed.map(LocalizedFormat.relative) ?? Messages.AppHomeView.neverPlayed.localized)
                .frame(minWidth: 80, maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            Divider().frame(height: 32)
            StatTile(label: Messages.AppHomeView.memory.localized, value: model.memoryLabel(instance))
                .frame(minWidth: 80, maxWidth: .infinity)
                .accessibilityElement(children: .combine)
        }
    }

    // MARK: Running and active work

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.running.localized)
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(running) { record in
                        HStack(spacing: 14) {
                            let instance = model.state.instances.first { $0.id == record.instanceID }
                            InstanceIcon(instance, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.instanceName).font(.headline).lineLimit(1)
                                InstanceMetadata(session: record)
                                Text(model.runningLabel(record.instanceID) ?? record.stage.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(Messages.AppHomeView.runHistory.localized) { model.showSession(record.id) }
                            if record.gameIdentity?.isAlive == true { Button(Messages.AppHomeView.returnToGame.localized) { model.returnToGame(record.instanceID) }.buttonStyle(.borderedProminent) }
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if record.id != running.last?.id { Divider().padding(.leading, 70) }
                    }
                }
            }
        }
    }

    private func activitySection(_ task: LauncherLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.inProgress.localized) { seeAll(Messages.AppHomeView.allTasks.localized) { model.page = .activity } }
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
            SectionTitle(Messages.AppHomeView.recentlyPlayed.localized)
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
            InstanceIcon(instance, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(instance.name).font(.headline).lineLimit(2)
                InstanceMetadata(instance: instance, compact: true)
                InstanceStatus(instance: instance)
                Text(instance.lastPlayedLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            LaunchButton(instance: instance, compact: true)
            InstanceMenu(instance: instance)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .contentShape(Rectangle())
        .onTapGesture { model.select(instance) }
        .help(Messages.AppHomeView.setAsFeaturedHint.localized)
        .contextMenu {
            Group {
                Button(Messages.AppHomeView.setAsFeatured.localized, systemImage: "house") { model.select(instance) }
                Button(Messages.AppHomeView.instanceSettings.localized, systemImage: "slider.horizontal.3") { model.editingInstance = instance }
                Button(Messages.AppHomeView.showInFinder.localized, systemImage: "folder") { model.reveal(instance) }
            }.labelStyle(.titleAndIcon)
        }
    }

    // MARK: Quick actions

    /// A shelf of equal tiles across the page, so the shortcuts read as a row
    /// of peers under the instance lists rather than a narrow side column.
    private func quickActions(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.AppHomeView.quickActions.localized)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 16) {
                ActionTile(symbol: "plus", title: Messages.AppHomeView.createInstance.localized, detail: Messages.AppHomeView.chooseVersionAndLoader.localized) { model.showCreate = true }
                ActionTile(symbol: "arrow.down", tint: .teal, title: Messages.AppHomeView.importPackAction.localized, detail: Messages.AppHomeView.supportedPackFormats.localized) { model.chooseInstanceImport() }
                ActionTile(symbol: "safari", tint: .indigo, title: Messages.AppHomeView.discoverContent.localized, detail: Messages.AppHomeView.browseContentSources.localized) { model.page = .discover }
                if model.activeAccount == nil {
                    ActionTile(symbol: "person.crop.circle.badge.plus", title: Messages.AppHomeView.addAccount.localized, detail: Messages.AppHomeView.accountRequired.localized) { model.showAccount = true }
                } else {
                    ActionTile(symbol: "cup.and.saucer.fill", tint: .orange, title: Messages.AppHomeView.javaRuntime.localized, detail: Messages.AppHomeView.detectOrDownloadJava.localized) { model.page = .java }
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
