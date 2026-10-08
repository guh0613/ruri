import Foundation

package struct MonitorLaunchRequest: Codable, Sendable {
    package init(version: Int, instanceID: UUID, sessionID: UUID, monitor: ProcessIdentity, plan: LaunchPlan, secrets: [String], storage: SessionLocationSnapshot, language: String? = nil, region: String? = nil) {
        self.version = version
        self.instanceID = instanceID
        self.sessionID = sessionID
        self.monitor = monitor
        self.plan = plan
        self.secrets = secrets
        self.storage = storage
        self.language = language
        self.region = region
    }

    package static let currentVersion = 1
    package let version: Int
    package let instanceID: UUID
    package let sessionID: UUID
    package let monitor: ProcessIdentity
    package let plan: LaunchPlan
    package let secrets: [String]
    package let storage: SessionLocationSnapshot
    package var language: String? = nil
    package var region: String? = nil
}
