import Foundation
import AppKit
import RuriCore

extension AppModel {
    func select(_ instance: GameInstance) {
        do { acceptState(try InstanceService(paths: basePaths).select(instance.id)) }
        catch { self.error = error.localizedDescription }
    }
    func setFavorite(_ favorite: Bool, for instance: GameInstance) {
        guard !readOnly else { return }
        do {
            _ = try InstanceService(paths: basePaths).edit(instance.id, favorite: favorite)
            acceptState(try StateStore.load(basePaths))
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func updateSettings(_ draft: GameInstance, basedOn original: GameInstance) -> Bool {
        guard !readOnly else { return false }
        do { acceptState(try ConfigurationService(paths: basePaths).saveInstanceSettings(draft, basedOn: original)) }
        catch { self.error = error.localizedDescription; return false }
        Task { await scanJava() }
        return !readOnly
    }
    func reveal(_ instance: GameInstance, folder: String? = nil) {
        let base = paths.game(instance.id)
        let url = folder.map { base.appendingPathComponent($0) } ?? base
        do {
            let location = try InstanceLocationLease.acquire(paths: paths, instanceID: instance.id)
            defer { withExtendedLifetime(location) {} }
            try paths.validateInstanceLocation(instance.id)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url)
        }
        catch { self.error = error.localizedDescription }
    }
    func trash(_ instance: GameInstance) {
        guard !isInstanceInUse(instance.id), !busy else { return }
        do {
            save(); guard !readOnly else { return }
            acceptState(try InstanceService(paths: basePaths).remove(instance.id))
        } catch { self.error = error.localizedDescription }
    }
}
