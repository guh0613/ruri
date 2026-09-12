import SwiftUI
import RuriCore

/// The three things players open most often on an instance, as a row of
/// icon buttons that sits next to the launch button on cards, rows and the
/// home page. Everything else stays in `InstanceMenu`.
struct InstanceQuickActions: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    var body: some View {
        HStack(spacing: 2) {
            action("实例设置", "slider.horizontal.3") { model.editingInstance = instance }
            action("管理模组与资源包", "puzzlepiece.extension") { model.contentInstance = instance }
            action("管理存档与备份", "globe") { model.worldInstance = instance }
        }
    }
    private func action(_ title: String, _ symbol: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.accessoryBar).help(title).accessibilityLabel(title)
    }
}
