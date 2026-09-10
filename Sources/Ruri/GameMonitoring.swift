import Foundation
import AppKit
import RuriCore

extension AppModel {
    func isInstanceInUse(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return activeSessions[id] != nil || pendingDirectoryCopyIDs.contains(id) || GameRunLease.isHeld(paths: paths, instanceID: id)
    }
    func runningLabel(_ id: UUID) -> String? {
        if pendingDirectoryCopyIDs.contains(id) || RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: id) { return "目录复制待恢复" }
        guard let record = activeSessions[id] else {
            if customDirectoryErrors[id] != nil { return "游戏目录无法访问" }
            return directoryErrors[paths.directoryID(for: id)] == nil ? nil : "文件夹无法访问"
        }
        switch GameMonitorClient.activity(record) {
        case .orphaned: return "监控已断开"
        case .uncertain: return "状态待确认"
        case .inactive: return nil
        case .monitoring:
            if record.state.isFinished { return "正在保存记录" }
            if record.stage == .quitting { return "等待游戏退出" }
            if record.stage == .stopping { return "正在终止进程" }
            return record.gameIdentity == nil ? "正在启动" : "运行中"
        }
    }
    func returnToGame(_ id: UUID) {
        guard let record = activeSessions[id] ?? sessions.first(where: { $0.instanceID == id && !$0.state.isFinished && $0.gameIdentity?.isAlive == true }) else { return }
        guard let identity = record.gameIdentity, identity.isAlive,
              let application = NSRunningApplication(processIdentifier: identity.pid), !application.isTerminated else {
            showSession(record.id); return
        }
        if application.activate(options: [.activateAllWindows]) { try? GameMonitorClient.recordEvent(.gameActivationRequested, paths: paths, session: record) }
        else { notice = "暂时无法切回游戏窗口，请从 Dock 或应用切换器选择游戏。" }
    }
    func requestGameQuit(_ instanceID: UUID) {
        guard let record = activeSessions[instanceID] else { return }
        do {
            try GameMonitorClient.requestNormalQuit(paths: paths, record: record)
            notice = "已提交正常退出请求，等待游戏处理。"; noticeSessionID = record.id
        } catch { notice = error.localizedDescription; noticeSessionID = record.id }
    }
    func confirmGameTermination(_ instanceID: UUID) {
        guard let record = activeSessions[instanceID], !record.state.isFinished, record.monitorIdentity?.isAlive == true else { return }
        let alert = NSAlert()
        alert.messageText = "终止“\(record.instanceName)”的游戏进程？"
        alert.informativeText = "这可能打断尚未完成的存档写入。仅在游戏无法正常退出时使用；如果游戏还能响应，请先返回游戏退出。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "终止进程")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try GameMonitorClient.requestStop(paths: paths, record: record) }
        catch { notice = error.localizedDescription; noticeSessionID = record.id }
    }
    func didRecoverSession(_ record: GameSession) async {
        publishSession(record)
        await readMonitorLog(record, final: true)
        logCursors.removeValue(forKey: record.id)
        if activeSessions[record.instanceID]?.id == record.id { activeSessions.removeValue(forKey: record.instanceID) }
        handledExits.insert(record.id)
        acknowledgeSession(record)
        notice = record.title; noticeSessionID = record.id
    }
    func showSession(_ id: UUID? = nil) {
        requestedLogSessionID = id ?? logsSessionID ?? sessions.first?.id
        openMainWindow?(); showLogs = true
    }
    func acknowledgeSession(_ record: GameSession) {
        do {
            try GameSessionReviewStore.mark(record, paths: paths)
            NSApp.dockTile.badgeLabel = sessions.contains(where: needsReview) ? "!" : nil
        } catch { notice = "无法保存运行记录的已读状态：\(error.localizedDescription)" }
    }
    private func reviewed(_ record: GameSession) -> Bool {
        (try? GameSessionReviewStore.contains(record, paths: paths)) ?? false
    }
    private func needsReview(_ record: GameSession) -> Bool {
        guard record.monitorIdentity != nil, !reviewed(record) else { return false }
        return record.state == .failed || (!record.state.isFinished && GameMonitorClient.activity(record) != .monitoring)
    }
    func recordClientEvent(_ event: GameMonitorClient.ClientEvent) {
        for record in activeSessions.values { try? GameMonitorClient.recordEvent(event, paths: paths, session: record) }
    }
    func startGameObservation() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                if activeSessions.isEmpty || tick % 4 == 0 { await refreshSessions() }
                else {
                    let records = Array(activeSessions.values), paths = paths
                    let updated = await Task.detached(priority: .utility) {
                        records.compactMap { try? GameSessionStore.load(paths: paths, instanceID: $0.instanceID, sessionID: $0.id) }
                    }.value
                    for record in updated { publishSession(record) }
                }
                await pollGames()
                tick += 1
                do { try await Task.sleep(for: activeSessions.isEmpty ? .seconds(2) : .milliseconds(500)) } catch { return }
            }
        }
    }
    func pollGames() async {
        let previous = activeSessions
        let snapshot = sessions, snapshotIDs = Set(sessions.map(\.id))
        var active: [UUID: GameSession] = [:]
        var presentedAttention = false
        for record in snapshot where record.monitorIdentity != nil {
            let activity = GameMonitorClient.activity(record)
            if activity != .inactive {
                if previous[record.instanceID]?.id != record.id { try? GameMonitorClient.recordEvent(.connected, paths: paths, session: record) }
                if active[record.instanceID] == nil { active[record.instanceID] = record }
                if logsSessionID == nil { logsSessionID = record.id }
                await readMonitorLog(record, final: false)
            } else if previous[record.instanceID]?.id == record.id {
                await readMonitorLog(record, final: true)
                logCursors.removeValue(forKey: record.id)
                if let exit = record.exit { lastGameExit = exit }
                notice = record.interruption != nil ? record.title : record.exit?.summary ?? "游戏进程已结束，监控没有留下退出原因。"
                noticeSessionID = record.id
            }
            if needsReview(record) && !handledExits.contains(record.id) {
                handledExits.insert(record.id)
                NSApp.dockTile.badgeLabel = "!"
                if !presentedAttention {
                    let summary = activity == .orphaned ? "游戏仍在运行，监控已中断" : activity == .uncertain ? "监控已中断，游戏状态待确认" : record.exit?.summary ?? record.title
                    notice = "\(record.instanceName)：\(summary)"
                    noticeSessionID = record.id
                    if NSApp.isActive && NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                        requestedLogSessionID = record.id; showLogs = true
                    }
                    presentedAttention = true
                }
            }
        }
        for (id, record) in activeSessions where !snapshotIDs.contains(record.id) { active[id] = record }
        // A recovery action may have completed while a log read yielded above.
        // Do not restore that action's older active snapshot into the UI.
        for (id, record) in active {
            if let latest = sessions.first(where: { $0.id == record.id }), latest != record {
                if GameMonitorClient.activity(latest) == .inactive { active.removeValue(forKey: id) }
                else { active[id] = latest }
            }
        }
        if activeSessions != active { activeSessions = active }
        restorePlaytime()
    }
    private func readMonitorLog(_ record: GameSession, final: Bool) async {
        do {
            let cursor: GameSessionLogCursor
            if let existing = logCursors[record.id] { cursor = existing }
            else {
                let paths = paths
                cursor = try await Task.detached(priority: .utility) { try GameSessionLogCursor(paths: paths, session: record) }.value
                logCursors[record.id] = cursor
            }
            var changed = try await cursor.refresh(final: final)
            if final { while try await cursor.refresh(final: true) { changed = true } }
            if changed || liveLogs[record.id] == nil { liveLogs[record.id] = await cursor.lines }
        } catch { notice = "无法读取 \(record.instanceName) 的运行日志：\(error.localizedDescription)"; noticeSessionID = record.id }
    }
    private func restorePlaytime() {
        var changed = false
        for index in state.instances.indices {
            let id = state.instances[index].id
            if let ledger = try? GamePlaytimeStore.load(paths: paths, instanceID: id) {
                if state.instances[index].playTime != ledger.total { state.instances[index].playTime = ledger.total; changed = true }
                if (state.instances[index].lastPlayed ?? .distantPast) < ledger.lastPlayed { state.instances[index].lastPlayed = ledger.lastPlayed; changed = true }
            }
        }
        if changed { save() }
    }
    func prepareToQuit() async {
        isQuitting = true
        bootTask?.cancel()
        operation?.cancel()
        await operation?.value
        monitorTask?.cancel()
    }
}
