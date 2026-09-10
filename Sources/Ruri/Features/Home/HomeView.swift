import SwiftUI
import AppKit
import RuriCore

struct HomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top) {
                        SectionHeading(title: "今天，想去哪里？", subtitle: "你的世界，在 Mac 上继续。")
                        Spacer()
                        Label(JavaRuntime.hostArchitecture == "aarch64" ? "Apple Silicon" : "Intel Mac", systemImage: "laptopcomputer").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }
                    hero
                    if let instance = model.selected {
                        HStack { Text("继续冒险").font(.title3.weight(.semibold)); Spacer(); Button("全部实例", systemImage: "arrow.right") { model.page = .library }.buttonStyle(.plain).font(.callout).foregroundStyle(Theme.accent) }
                        Surface {
                            HStack(spacing: 16) {
                                InstanceIcon(loader: instance.loader, size: 60)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(instance.name).font(.headline)
                                    Text(instance.subtitle).font(.callout).foregroundStyle(.secondary)
                                    HStack(spacing: 8) { TagPill(text: model.runningLabel(instance.id) ?? (instance.installed ? "就绪" : "未完成安装")); Text(instance.lastPlayed.map { "上次游玩 \($0.formatted(.relative(presentation: .named)))" } ?? "一个全新的开始").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                launchButton(instance)
                            }
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: geometry.size.width >= 750 ? 3 : geometry.size.width >= 480 ? 2 : 1), spacing: 16) {
                        quickCard("建立新世界", detail: "原版与主流模组加载器", symbol: "plus.square.on.square", action: { model.showCreate = true })
                        quickCard("发现更多可能", detail: "模组、光影与整合包", symbol: "sparkles", action: { model.page = .discover })
                        quickCard("准备好出发", detail: model.activeAccount == nil ? "添加你的 Minecraft 账号" : "管理账号与玩家身份", symbol: "person.crop.circle", action: { model.page = .accounts })
                    }
                    HStack(spacing: 7) {
                        Circle().fill(model.catalog == nil ? Color.orange : Theme.accent).frame(width: 5, height: 5)
                        Text(model.catalog.map { "最新正式版 \($0.latest.release)" } ?? (model.catalogLoading ? "正在获取版本信息…" : "暂时无法获取版本信息"))
                        Spacer(); Text("用心为 macOS 打造").foregroundStyle(.tertiary)
                    }.font(.caption).foregroundStyle(.secondary)
                }.padding(30).frame(maxWidth: 1250)
            }
        }
    }
    private var hero: some View {
        ZStack(alignment: .leading) {
            Landscape()
            LinearGradient(colors: [Theme.sand.opacity(0.97), Theme.sand.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 18) {
                Text("A LITTLE WONDER. A WHOLE NEW WORLD.").font(.system(size: 9, weight: .bold)).tracking(1.7).foregroundStyle(Theme.ink.opacity(0.6))
                Text("下一个世界，\n从这里开始。").font(.system(size: 35, weight: .bold, design: .rounded)).lineSpacing(6).foregroundStyle(Theme.ink)
                Text("熟悉的方块，无限的可能。\n选择一个版本，让冒险自然发生。").font(.system(size: 12)).lineSpacing(5).foregroundStyle(Theme.ink.opacity(0.7))
                Button { model.showCreate = true } label: { Label("创建游戏实例", systemImage: "plus").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 6) }.buttonStyle(.borderedProminent).tint(Theme.ink).disabled(model.busy)
            }.padding(32)
        }.frame(height: 295).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func quickCard(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Surface {
                VStack(alignment: .leading, spacing: 11) {
                    HStack { Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(Theme.accent); Spacer(); Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.tertiary) }
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
    private func launchButton(_ instance: GameInstance) -> some View { LaunchButton(instance: instance) }
}
