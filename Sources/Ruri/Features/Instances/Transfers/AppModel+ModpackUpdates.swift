import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func prepareModpackUpdate(_ prepared: PreparedInstanceImport, instance: GameInstance, keepJVMArguments: Bool, curseFiles: [PlannedCurseFile], manualFiles: [Int: URL],
                              completion: @MainActor @Sendable @escaping (PreparedModpackUpdate) -> Void) {
        perform(Messages.AppAppModelModpackUpdates.preparingModpackUpdate(instance.name)) { [self] id in
            let downloader = await installer.downloader
            let content = try await CurseForgeService(apiKey: "").materialize(curseFiles, paths: paths, downloader: downloader, manualFiles: manualFiles) { [weak self] p in await self?.progress(id, p) }
            let plan = try await ModpackUpdater(paths: paths, downloader: downloader).prepare(prepared, for: instance, keepJVMArguments: keepJVMArguments, content: content, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
            await InstanceTransfer(paths: paths).discard(prepared)
            completion(plan)
        }
    }
    func applyModpackUpdate(_ plan: PreparedModpackUpdate, keeping: Set<String>, completion: @MainActor @Sendable @escaping () -> Void) {
        save()
        perform(Messages.AppAppModelModpackUpdates.applyingModpackUpdate(plan.instance.name)) { [self] id in
            let service = await ModpackUpdater(paths: paths, downloader: installer.downloader)
            let saved = try await service.apply(plan, keepingLocal: keeping, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
            acceptState(saved); report(Messages.AppAppModelModpackUpdates.modpackUpdated(plan.instance.name, String(describing: plan.incoming.version))); completion()
        }
    }
    func rollbackModpack(_ instance: GameInstance, completion: @MainActor @Sendable @escaping () -> Void) {
        save()
        perform(Messages.AppAppModelModpackUpdates.rollingBackModpackUpdate(instance.name)) { [self] _ in
            let result = try await ModpackUpdater(paths: paths).rollback(instance)
            acceptState(result.state)
            report(result.preservedFiles == 0 ? Messages.AppAppModelModpackUpdates.modpackRollbackComplete : Messages.AppAppModelModpackUpdates.modpackRollbackPreservedChanges(Int64(result.preservedFiles)), level: result.preservedFiles == 0 ? .success : .warning)
            completion()
        }
    }
    func recoverModpackUpdate(_ instance: GameInstance, completion: @MainActor @Sendable @escaping () -> Void) {
        perform(Messages.AppAppModelModpackUpdates.recoveringModpackUpdate(instance.name)) { [self] _ in
            let paths = paths
            let saved = try await Task.detached(priority: .userInitiated) { try ModpackUpdateStore.recover(instanceID: instance.id, paths: paths) }.value
            acceptState(saved); report(Messages.AppAppModelModpackUpdates.modpackUpdateRecovered); completion()
        }
    }
}
