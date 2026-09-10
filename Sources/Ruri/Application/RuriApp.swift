import SwiftUI
import AppKit
import RuriCore

@main struct RuriApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(RuriLifecycle.self) private var lifecycle
    var body: some Scene {
        Window("Ruri", id: "main") {
            MainWindowContent(model: model, lifecycle: lifecycle)
        }
        .defaultSize(width: 1140, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("显示主窗口") { model.openMainWindow?() }.keyboardShortcut("0")
                Divider()
                Button("新建游戏实例") { model.openMainWindow?(); model.showCreate = true }.keyboardShortcut("n").disabled(model.busy)
                Button("导入实例或整合包…") { model.openMainWindow?(); model.chooseInstanceImport() }.keyboardShortcut("i").disabled(model.busy)
                Button("查看已有 Minecraft 目录…") { model.openMainWindow?(); model.chooseMinecraftDirectory() }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(model.busy)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { model.openMainWindow?(); model.page = .settings }.keyboardShortcut(",")
            }
            CommandMenu("游戏") {
                Button("启动选中实例") { if let instance = model.selected { model.launch(instance) } }.keyboardShortcut("r").disabled(model.selected == nil || model.busy || model.isInstanceInUse(model.selected?.id))
                ForEach(model.activeSessions.values.sorted { $0.createdAt < $1.createdAt }) { record in
                    Button("返回 \(record.instanceName)") { model.returnToGame(record.instanceID) }
                    if record.nativeQuitSupported == true {
                        Button("请求退出 \(record.instanceName)") { model.requestGameQuit(record.instanceID) }.disabled(record.state.isFinished || record.gameIdentity?.isAlive != true || record.monitorIdentity?.isAlive != true)
                    }
                    Button("终止 \(record.instanceName) 的进程…") { model.confirmGameTermination(record.instanceID) }.disabled(record.state.isFinished || record.monitorIdentity?.isAlive != true)
                }
                Button("运行记录与日志") { model.showSession() }.keyboardShortcut("l")
                Divider()
                Button("在 Finder 中显示实例") { if let instance = model.selected { model.reveal(instance) } }.keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.selected == nil)
            }
        }
    }
}

private struct MainWindowContent: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel
    let lifecycle: RuriLifecycle
    var body: some View {
        RootView().environment(model)
            .onAppear {
                lifecycle.model = model
                let action = openWindow
                model.openMainWindow = { action(id: "main"); NSApp.activate() }
            }
            .onOpenURL { url in
                if ["mrpack", "zip"].contains(url.pathExtension.lowercased()) {
                    model.pendingOpenURLs.append(url); model.openMainWindow?()
                }
            }
            .task(id: model.pendingOpenURLs.first) {
                guard model.pendingOpenURLs.first != nil else { return }
                while model.busy || model.showLogs || model.showCreate || model.showAccount || model.importingInstance != nil || model.minecraftDirectory != nil || model.exportingInstance != nil {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
                guard !Task.isCancelled, let url = model.pendingOpenURLs.first else { return }
                model.pendingOpenURLs.removeFirst(); model.importPack(url)
            }
    }
}

@MainActor final class RuriLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { model?.recordClientEvent(.windowClosed); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model?.recordClientEvent(.windowReopened); model?.openMainWindow?() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.recordClientEvent(.quitRequested)
        guard let model, model.operation != nil else { model?.monitorTask?.cancel(); model?.bootTask?.cancel(); return .terminateNow }
        if !model.isQuitting {
            Task { await model.prepareToQuit(); sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let show = NSMenuItem(title: "显示 Ruri", action: #selector(showMain(_:)), keyEquivalent: "")
        show.target = self; menu.addItem(show)
        for record in model?.activeSessions.values.sorted(by: { $0.createdAt < $1.createdAt }) ?? [] where record.gameIdentity?.isAlive == true {
            let item = NSMenuItem(title: "返回 \(record.instanceName)", action: #selector(returnGame(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = record.instanceID.uuidString; menu.addItem(item)
        }
        return menu
    }
    @objc private func showMain(_ sender: NSMenuItem) { model?.openMainWindow?() }
    @objc private func returnGame(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        model?.returnToGame(id)
    }
}
