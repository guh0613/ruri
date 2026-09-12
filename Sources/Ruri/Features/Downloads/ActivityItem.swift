import RuriLocalization
import Foundation
import RuriCore

struct ActivityItem: Identifiable {
    enum Status { case running, completed, failed, cancelled }
    let id = UUID()
    var titleMessage: LocalizedMessage
    var title: String { titleMessage.localized }
    var progress = InstallProgress(Messages.AppActivityItem.preparing)
    var status = Status.running
    var error: String?
    let startedAt = Date()
}
