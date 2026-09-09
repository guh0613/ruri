import SwiftUI
import AppKit
import RuriCore

@main struct RuriApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup("Ruri") {
            RootView().environment(model)
                .onOpenURL { url in if ["mrpack", "zip"].contains(url.pathExtension.lowercased()) { model.importPack(url) } }
        }
        .defaultSize(width: 1140, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建游戏实例") { model.showCreate = true }.keyboardShortcut("n").disabled(model.busy)
                Button("导入实例或整合包…") { model.chooseInstanceImport() }.keyboardShortcut("i").disabled(model.busy)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { model.page = .settings }.keyboardShortcut(",")
            }
            CommandMenu("游戏") {
                Button("启动选中实例") { if let instance = model.selected { model.launch(instance) } }.keyboardShortcut("r").disabled(model.selected == nil || model.busy || model.runningID != nil)
                Button("结束游戏") { model.stopGame() }.disabled(model.runningID == nil)
                Button("运行记录与日志") { model.showLogs = true }.keyboardShortcut("l")
                Divider()
                Button("在 Finder 中显示实例") { if let instance = model.selected { model.reveal(instance) } }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.selected == nil)
            }
        }
    }
}
