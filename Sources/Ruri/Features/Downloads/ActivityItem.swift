import Foundation
import RuriCore

struct ActivityItem: Identifiable {
    enum Status { case running, completed, failed, cancelled }
    let id = UUID()
    var title: String
    var progress = InstallProgress("准备中")
    var status = Status.running
    var error: String?
    let startedAt = Date()
}
