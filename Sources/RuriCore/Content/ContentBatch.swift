import Foundation

extension ContentManager {
    /// Evaluate dependencies after applying the entire selection, independent
    /// of row order. The existing journal also serves batch file operations.
    public func setEnabled(_ enabled: Bool, files: [LocalContentFile]) throws {
        try lock(); defer { unlock() }
        try recover(); try Task.checkCancellation()
        let records = try readRecords()
        let selected = try validateSelection(files, records: records).filter { $0.enabled != enabled }
        guard !selected.isEmpty else { return }
        let ids = Set(selected.compactMap { $0.managed?.id })
        let future = records.map { item in var item = item; if ids.contains(item.id) { item.enabled = enabled }; return item }
        try checkDependencies(original: records, future: future, changedIDs: ids)
        let moves = try selected.map { file -> (String, String) in
            let source = relativePath(file), target = file.kind.folder + "/" + file.filename + (enabled ? "" : ".disabled")
            guard !FileManager.default.fileExists(atPath: try contentURL(target).path) else { throw RuriError.message("目标文件已存在，整批操作尚未执行：\(target)") }
            return (source, target)
        }
        let affected = Array(Set(moves.flatMap { [$0.0, $0.1] })).sorted()
        try changeFiles(affected: affected, oldRecords: records) {
            for (source, target) in moves { try FileManager.default.moveItem(at: contentURL(source), to: contentURL(target)) }
            try writeRecords(future)
        }
    }

    @discardableResult public func remove(_ files: [LocalContentFile]) throws -> URL? {
        try lock(); defer { unlock() }
        try recover(); try Task.checkCancellation()
        let records = try readRecords(), selected = try validateSelection(files, records: records)
        guard !selected.isEmpty else { return nil }
        let ids = Set(selected.compactMap { $0.managed?.id })
        let future = records.filter { !ids.contains($0.id) }
        try checkDependencies(original: records, future: future, changedIDs: ids)
        let affected = selected.map(relativePath)
        var trashed: NSURL?
        do {
            try changeFiles(affected: affected, oldRecords: records) {
                let fm = FileManager.default
                if affected.count == 1 {
                    try fm.trashItem(at: contentURL(affected[0]), resultingItemURL: &trashed)
                } else {
                    let bundle = transactionURL.appendingPathComponent("Ruri 已移除的内容 " + String(UUID().uuidString.prefix(8)))
                    for path in affected {
                        let destination = try LauncherPaths.safePath(path, within: bundle)
                        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.moveItem(at: contentURL(path), to: destination)
                    }
                    try fm.trashItem(at: bundle, resultingItemURL: &trashed)
                }
                try writeRecords(future)
            }
        } catch {
            // Delete only our redundant Trash copy after recovery has restored
            // every original and removed the transaction. Failed recovery keeps it.
            if !FileManager.default.fileExists(atPath: transactionURL.path), let trashed { try? FileManager.default.removeItem(at: trashed as URL) }
            throw error
        }
        return trashed.map { $0 as URL }
    }

    private func relativePath(_ file: LocalContentFile) -> String { file.kind.folder + "/" + file.filename + (file.enabled ? "" : ".disabled") }
    private func validateSelection(_ files: [LocalContentFile], records: [ManagedContent]) throws -> [LocalContentFile] {
        guard Set(files.map(\.id)).count == files.count else { throw RuriError.message("选择中包含重复文件。") }
        for file in files {
            let path = relativePath(file), expected = try contentURL(path)
            let info = try expected.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard expected.standardizedFileURL.resolvingSymlinksInPath() == file.url.standardizedFileURL.resolvingSymlinksInPath(), info.isRegularFile == true, Int64(info.fileSize ?? -1) == file.size,
                  records.first(where: { $0.relativePath == path }) == file.managed else {
                throw RuriError.message("内容列表已改变，请刷新后重新选择：\(file.filename)")
            }
        }
        return files
    }
    private func checkDependencies(original: [ManagedContent], future: [ManagedContent], changedIDs: Set<String>) throws {
        func key(_ record: ManagedContent, project: String? = nil) -> String { record.provider + ":" + (project ?? record.projectID) }
        let oldByID = Dictionary(original.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let present = try future.filter { record in
            guard record.enabled, let old = oldByID[record.id] else { return false }
            return FileManager.default.fileExists(atPath: try contentURL(old.relativePath).path)
        }
        let available = Set(present.map { key($0) })
        let changed = Set(original.filter { changedIDs.contains($0.id) }.map { key($0) })
        for record in present {
            let missing = record.requiredProjects.filter { project in
                let dependency = key(record, project: project)
                return !available.contains(dependency) && (changedIDs.contains(record.id) || changed.contains(dependency))
            }
            guard missing.isEmpty else { throw RuriError.message("“\(record.title)”需要 \(missing.joined(separator: "、"))。请将依赖与模组一起启用，或把依赖它的模组一起停用/移除。整批操作尚未执行。") }
        }
    }

    /// Call with the content operation lock held and after all validation.
    func changeFiles(affected: [String], oldRecords: [ManagedContent], action: () throws -> Void) throws {
        let fm = FileManager.default
        var originals: [String] = []
        do {
            for path in affected {
                try Task.checkCancellation()
                let source = try contentURL(path)
                if fm.fileExists(atPath: source.path) {
                    let attributes = try fm.attributesOfItem(atPath: source.path)
                    guard attributes[.type] as? FileAttributeType == .typeRegular else { throw RuriError.message("内容目录中存在不支持的文件类型：\(path)") }
                    let backup = try LauncherPaths.safePath(path, within: transactionURL.appendingPathComponent("backups"))
                    try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: source, to: backup); originals.append(path)
                }
            }
            try fm.createDirectory(at: transactionURL, withIntermediateDirectories: true)
            let journal = Journal(affected: affected, originals: originals, oldRecords: oldRecords)
            try JSONEncoder().encode(journal).write(to: transactionURL.appendingPathComponent("journal.json"), options: .atomic)
            // Finish or restore the whole short commit once its journal exists.
            try action()
            try Data().write(to: transactionURL.appendingPathComponent("committed"), options: .atomic)
        } catch {
            do { try recover() } catch { throw RuriError.message("内容操作恢复失败，备份保留在 \(transactionURL.path)。\(error.localizedDescription)") }
            throw error
        }
        try? fm.removeItem(at: transactionURL)
    }
}
