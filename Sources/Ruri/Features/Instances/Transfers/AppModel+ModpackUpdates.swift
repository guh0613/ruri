import Foundation
import RuriCore

extension AppModel {
    func prepareModpackUpdate(_ prepared: PreparedInstanceImport, instance: GameInstance, keepJVMArguments: Bool, curseFiles: [PlannedCurseFile], manualFiles: [Int: URL],
                              completion: @MainActor @Sendable @escaping (PreparedModpackUpdate) -> Void) {
        perform("准备 \(instance.name) 的整合包更新") { [self] id in
            let downloader = await installer.downloader
            let content = try await CurseForgeService(apiKey: "").materialize(curseFiles, paths: paths, downloader: downloader, manualFiles: manualFiles) { [weak self] p in await self?.progress(id, p) }
            let plan = try await ModpackUpdater(paths: paths, downloader: downloader).prepare(prepared, for: instance, keepJVMArguments: keepJVMArguments, content: content, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
            await InstanceTransfer(paths: paths).discard(prepared)
            completion(plan)
        }
    }
    func applyModpackUpdate(_ plan: PreparedModpackUpdate, keeping: Set<String>, completion: @MainActor @Sendable @escaping () -> Void) {
        save()
        perform("更新 \(plan.instance.name)") { [self] id in
            let service = await ModpackUpdater(paths: paths, downloader: installer.downloader)
            let saved = try await service.apply(plan, keepingLocal: keeping, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
            acceptState(saved); notice = "\(plan.instance.name) 已更新至 \(plan.incoming.version)"; completion()
        }
    }
    func rollbackModpack(_ instance: GameInstance, completion: @MainActor @Sendable @escaping () -> Void) {
        save()
        perform("回退 \(instance.name) 的整合包更新") { [self] _ in
            let result = try await ModpackUpdater(paths: paths).rollback(instance)
            acceptState(result.state)
            notice = result.preservedFiles == 0 ? "已回退上次整合包更新" : "已回退整合包，保留了 \(result.preservedFiles) 项更新后的本地修改"
            completion()
        }
    }
    func recoverModpackUpdate(_ instance: GameInstance, completion: @MainActor @Sendable @escaping () -> Void) {
        perform("恢复 \(instance.name) 的整合包更新") { [self] _ in
            let paths = paths
            let saved = try await Task.detached(priority: .userInitiated) { try ModpackUpdateStore.recover(instanceID: instance.id, paths: paths) }.value
            acceptState(saved); notice = "整合包更新记录已恢复"; completion()
        }
    }
}
