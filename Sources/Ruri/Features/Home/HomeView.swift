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
            Label("还没有游戏实例", systemImage: "square.grid.2x2")
        } description: {
            Text("新建一个实例，或导入整合包开始游戏。")
        } actions: {
            Button("新建实例") { model.showCreate = true }.buttonStyle(.borderedProminent)
            Button("导入整合包…") { model.chooseInstanceImport() }
        }
        .disabled(model.busy)
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: Continue playing

    private func featuredSection(_ instance: GameInstance) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("继续游戏") { seeAll("全部实例") { model.page = .library } }
            Surface(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 20) {
                        Button { model.editingInstance = instance } label: {
                            InstanceIcon(loader: instance.loader, size: 84, png: instance.iconPNG)
                        }.buttonStyle(.plain).help("更换图标或编辑实例设置")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(instance.name).font(.title2.weight(.semibold)).lineLimit(1)
                            Text(instance.subtitle).foregroundStyle(.secondary).lineLimit(1)
                            statusLine(instance).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 24)
                        InstanceQuickActions(instance: instance).controlSize(.large)
                        LaunchButton(instance: instance, size: .large).padding(.leading, 6)
                        InstanceMenu(instance: instance, showsSelect: false) { Image(systemName: "ellipsis.circle").font(.title3) }
                            .padding(.leading, 4)
                    }
                    .padding(24)
                    Divider()
                    HStack(spacing: 16) {
                        StatTile(label: "游玩时长", value: instance.playTimeLabel)
                        Divider().frame(height: 28)
                        StatTile(label: "上次游玩", value: instance.lastPlayed?.formatted(.relative(presentation: .named)) ?? "尚未游玩")
                        Divider().frame(height: 28)
                        StatTile(label: "游戏版本", value: "\(instance.gameVersion) · \(instance.loaderLabel)")
                        Divider().frame(height: 28)
                        StatTile(label: "内存", value: model.memoryLabel(instance))
                    }
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    if model.activeAccount == nil {
                        Divider()
                        HStack {
                            Label("还没有账号。启动前需要添加 Microsoft 账号、外置认证账号或离线账号。", systemImage: "person.crop.circle.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("添加账号") { model.showAccount = true }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 14)
                    }
                }
            }
        }
    }

    private func statusLine(_ instance: GameInstance) -> some View {
        HStack(spacing: 6) {
            Circle().fill(model.statusColor(instance)).frame(width: 7, height: 7)
            Text(model.runningLabel(instance.id) ?? (instance.installed ? "就绪" : "未完成安装"))
            if let issue = instance.repositoryIssue { Text("·").foregroundStyle(.tertiary); Text(issue).lineLimit(1).help(issue) }
        }
    }

    // MARK: Running and active work

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("正在运行")
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
                            Button("运行记录") { model.showSession(record.id) }
                            if record.gameIdentity?.isAlive == true { Button("返回游戏") { model.returnToGame(record.instanceID) }.buttonStyle(.borderedProminent) }
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if record.id != running.last?.id { Divider().padding(.leading, 70) }
                    }
                }
            }
        }
    }

    private func activitySection(_ task: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("正在进行") { seeAll("全部任务") { model.page = .downloads } }
            Surface {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(task.title).font(.headline).lineLimit(1); Spacer(); Button("取消") { model.operation?.cancel() }.controlSize(.small) }
                    if task.progress.total > 0 { ProgressView(value: task.progress.fraction) } else { ProgressView().controlSize(.small) }
                    HStack { Text(task.progress.stage).lineLimit(1); Spacer(); if task.progress.total > 0 { Text("\(task.progress.completed) / \(task.progress.total)").monospacedDigit() } }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Recently played

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("最近游玩")
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
        .help("点按后在“继续游戏”中显示")
        .contextMenu {
            Button("在“继续游戏”中显示") { model.select(instance) }
            Button("实例设置", systemImage: "slider.horizontal.3") { model.editingInstance = instance }
            Button("在 Finder 中显示", systemImage: "folder") { model.reveal(instance) }
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("快捷操作")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 14)], spacing: 14) {
                ActionTile(symbol: "plus.square", title: "新建实例", detail: "选择游戏版本和加载器") { model.showCreate = true }
                ActionTile(symbol: "square.and.arrow.down", title: "导入整合包", detail: "mrpack、CurseForge、HMCL 等格式") { model.chooseInstanceImport() }
                ActionTile(symbol: "safari", title: "发现内容", detail: "浏览 Modrinth 与 CurseForge") { model.page = .discover }
                if model.activeAccount == nil {
                    ActionTile(symbol: "person.crop.circle.badge.plus", title: "添加账号", detail: "启动游戏前需要一个账号") { model.showAccount = true }
                } else {
                    ActionTile(symbol: "cup.and.saucer", title: "Java 运行时", detail: "检测本机 Java 或下载官方运行时") { model.page = .java }
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
