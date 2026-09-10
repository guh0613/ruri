import SwiftUI
import AppKit
import RuriCore

struct LaunchButton: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    var body: some View {
        Button { if model.activeSessions[instance.id] != nil { model.returnToGame(instance.id) } else { model.launch(instance) } } label: {
            Label(model.activeSessions[instance.id] != nil ? (model.activeSessions[instance.id]?.gameIdentity?.isAlive == true ? "返回游戏" : "查看运行记录") : instance.installed ? "启动游戏" : "继续安装", systemImage: model.activeSessions[instance.id] != nil ? "arrow.up.forward.app" : "play.fill").padding(.horizontal, 15).padding(.vertical, 9)
        }.buttonStyle(.borderedProminent).disabled(model.activeSessions[instance.id] == nil && (model.busy || model.isInstanceInUse(instance.id)))
    }
}
