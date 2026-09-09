import SwiftUI
import RuriCore

struct GameQuitControls: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let attempt = session.normalQuitAttempt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attempt.explanation).font(.caption).foregroundStyle(.secondary)
                        if attempt.accepted && context.date.timeIntervalSince(attempt.processedAt) >= 20 {
                            Text("游戏还未退出。可能正在保存或等待操作，可以返回游戏查看；Ruri 会继续等待。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if session.nativeQuitSupported != true {
                Text("本次启动请通过游戏菜单正常退出。").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("返回游戏") { model.returnToGame(session.instanceID) }.disabled(session.gameIdentity?.isAlive != true)
                Spacer()
                if session.nativeQuitSupported == true {
                    Button(session.normalQuitAttempt?.accepted == true ? "再次请求退出" : "请求正常退出") { model.requestGameQuit(session.instanceID) }
                        .disabled(session.gameIdentity?.isAlive != true || session.stage == .stopping)
                }
                Menu {
                    Button("终止游戏进程…", role: .destructive) { model.confirmGameTermination(session.instanceID) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("游戏没有响应时的操作")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
