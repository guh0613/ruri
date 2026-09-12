import SwiftUI
import AppKit
import RuriCore

/// The landing page: the instance to play next, what is running or
/// installing right now, and the other instances played recently.
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
            if model.directoryInstances.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 40) {
                    if let featured { featuredSection(featured) }
                    if !running.isEmpty { runningSection }
                    if let task = model.activeActivity { activitySection(task) }
                    if !recent.isEmpty { recentSection }
                }
                .padding(.horizontal, 40).padding(.vertical, 36).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
            }
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
        .frame(maxWidth: .infinity, minHeight: 480)
    }

    private func featuredSection(_ instance: GameInstance) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("继续游戏") { seeAll("全部实例") { model.page = .library } }
            Surface(padding: 24) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 20) {
                        InstanceIcon(loader: instance.loader, size: 80, png: instance.iconPNG)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(instance.name).font(.title2.weight(.semibold)).lineLimit(1)
                            Text(instance.subtitle).foregroundStyle(.secondary).lineLimit(1)
                            statusLine(instance).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 24)
                        LaunchButton(instance: instance, size: .large)
                        Menu {
                            Button("实例设置", systemImage: "slider.horizontal.3") { model.editingInstance = instance }
                            Button("管理模组与资源包", systemImage: "puzzlepiece.extension") { model.contentInstance = instance }
                            Button("管理存档与备份", systemImage: "globe") { model.worldInstance = instance }
                            Divider()
                            Button("在 Finder 中显示", systemImage: "folder") { model.reveal(instance) }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().padding(.leading, 4).help("更多操作")
                    }
                    if model.activeAccount == nil {
                        Divider()
                        HStack {
                            Label("还没有账号。启动前需要添加 Microsoft 账号、外置认证账号或离线账号。", systemImage: "person.crop.circle.badge.exclamationmark").font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("添加账号") { model.showAccount = true }
                        }
                    }
                }
            }
        }
    }

    private func statusLine(_ instance: GameInstance) -> some View {
        let status = model.runningLabel(instance.id)
        return HStack(spacing: 6) {
            Circle().fill(status != nil ? Color.orange : instance.installed ? Theme.accent : Color.orange).frame(width: 6, height: 6)
            Text(status ?? (instance.installed ? "就绪" : "未完成安装"))
            Text("·").foregroundStyle(.tertiary)
            Text(lastPlayed(instance))
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("正在运行")
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(running) { record in
                        HStack(spacing: 14) {
                            let instance = model.state.instances.first { $0.id == record.instanceID }
                            InstanceIcon(loader: instance?.loader ?? .vanilla, size: 36, png: instance?.iconPNG)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.instanceName).font(.headline).lineLimit(1)
                                Text(model.runningLabel(record.instanceID) ?? record.stage.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("运行记录") { model.showSession(record.id) }
                            if record.gameIdentity?.isAlive == true { Button("返回游戏") { model.returnToGame(record.instanceID) }.buttonStyle(.borderedProminent) }
                        }.padding(.horizontal, 16).padding(.vertical, 12)
                        if record.id != running.last?.id { Divider().padding(.leading, 66) }
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

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("最近游玩")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 400), spacing: 16)], spacing: 16) {
                ForEach(recent) { instance in recentCard(instance) }
            }
        }
    }

    private func recentCard(_ instance: GameInstance) -> some View {
        Surface(padding: 16) {
            HStack(spacing: 14) {
                InstanceIcon(loader: instance.loader, size: 52, png: instance.iconPNG)
                VStack(alignment: .leading, spacing: 4) {
                    Text(instance.name).font(.headline).lineLimit(1)
                    Text(instance.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Text(model.runningLabel(instance.id) ?? lastPlayed(instance)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 12)
                LaunchButton(instance: instance, compact: true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { model.select(instance) }
        .help("点按后在“继续游戏”中显示")
        .contextMenu {
            Button("在“继续游戏”中显示") { model.select(instance) }
            Button("实例设置", systemImage: "slider.horizontal.3") { model.editingInstance = instance }
            Button("在 Finder 中显示", systemImage: "folder") { model.reveal(instance) }
        }
    }

    private func seeAll(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) { Text(title); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
    }

    private func lastPlayed(_ instance: GameInstance) -> String {
        instance.lastPlayed.map { "上次游玩 " + $0.formatted(.relative(presentation: .named)) } ?? "尚未游玩"
    }
}
