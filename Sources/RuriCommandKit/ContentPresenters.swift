import Foundation
import RuriCore
import RuriLocalization

/// Catalog projects, installed content, modpacks, worlds, data packs and schematics.
extension CommandTextRenderer {
    // MARK: Catalog

    static func provider(_ value: Value) -> String {
        switch value.string { case "modrinth"?: "Modrinth"; case "curseforge"?: "CurseForge"; default: plain(value) }
    }

    /// The first values, then how many more there are.
    static func abbreviated(_ values: [String], keeping count: Int = 3) -> String {
        values.count <= count ? values.joined(separator: ", ") : Messages.CLIExperience.andMore(values.prefix(count - 1).joined(separator: ", "), String(values.count - count + 1)).localized
    }

    func projects(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnTitle.localized) { Self.plain($0["title"]) },
            ListColumn(header: Messages.CLIExperience.labelType.localized, priority: 1) { Self.plain($0["type"]) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { Self.plain($0["id"]) },
            ListColumn(header: Messages.CLIExperience.labelProvider.localized, detailOnly: true) { Self.provider($0["provider"]) },
            ListColumn(header: Messages.CLIExperience.labelPage.localized, detailOnly: true) { Self.plain($0["pageURL"]) }
        ])
    }

    /// A project's facts, then the start of its description.
    func project(_ value: Value) -> [String] {
        let project = value["project"]
        var lines = layout.prose(Self.plain(project["title"]), style.bold)
        lines += layout.fields([(Messages.CLIExperience.labelType.localized, Self.plain(project["type"])), (Messages.CLIExperience.labelProvider.localized, Self.provider(project["provider"])),
                                (Messages.CLIExperience.labelID.localized, Self.plain(project["id"])), (Messages.CLIExperience.labelLicense.localized, Self.plain(value["license"])),
                                (Messages.CLIExperience.labelPage.localized, Self.plain(project["pageURL"]))])
        var text = value["description"].string ?? ""
        if value["isHTML"] == .bool(true) { text = Self.textFromHTML(text) }
        let description = layout.paragraph(Self.printable(text.trimmingCharacters(in: .whitespacesAndNewlines)), indent: 2)
            .reduce(into: [String]()) { result, line in if !(line.isEmpty && result.last?.isEmpty != false) { result.append(line) } }
        guard !description.isEmpty else { return lines }
        let limit = 12
        lines += [""] + (layout.details ? description : Array(description.prefix(limit)))
        if !layout.details && description.count > limit { lines += layout.prose(Messages.CLIExperience.fullDescription.localized, style.dim) }
        else if value["descriptionTruncated"] == .bool(true) { lines += layout.prose(Messages.CLIExperience.descriptionTruncated.localized, style.dim) }
        return lines
    }

    static func textFromHTML(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<(br|/p|/div|/li|/h[1-6])[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { text = text.replacingOccurrences(of: entity, with: character) }
        return text
    }

    func projectVersions(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { Self.plain($0["number"]) },
            ListColumn(header: Messages.CLIExperience.columnChannel.localized, priority: 2) { Self.plain($0["channel"]) },
            ListColumn(header: Messages.CLIExperience.columnLoaders.localized, priority: 1) { $0["loaders"].strings.joined(separator: ", ") },
            ListColumn(header: Messages.CLIExperience.columnGameVersions.localized, priority: 3) { Self.abbreviated($0["gameVersions"].strings) },
            ListColumn(header: Messages.CLIExperience.columnPublished.localized, priority: 4) { TextFormat.date($0["publishedAt"]) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { Self.plain($0["id"]) },
            ListColumn(header: Messages.CLIExperience.labelFile.localized, detailOnly: true) { Self.plain($0["filename"]) },
            ListColumn(header: Messages.CLIExperience.labelSize.localized, detailOnly: true) { TextFormat.bytes($0["bytes"]) }
        ])
    }

    func categories(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) },
            ListColumn(header: Messages.CLIExperience.labelType.localized, priority: 1) { Self.plain($0["type"]) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { Self.plain($0["id"]) }
        ])
    }

    // MARK: Content

    static func contentKind(_ value: Value) -> String { ContentKind(rawValue: value.string ?? "")?.title ?? plain(value) }

    private func enabled(_ value: Value) -> String {
        value["enabled"] == .bool(false) ? style.dim(Messages.CLIExperience.statusDisabled.localized) : Messages.CLIExperience.statusEnabled.localized
    }

    func contentFiles(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnTitle.localized) { Self.plain($0["title"]) },
            ListColumn(header: Messages.CLIExperience.columnVersion.localized, priority: 2) { Self.plain($0["version"]) },
            ListColumn(header: Messages.CLIExperience.columnStatus.localized, priority: 1) { enabled($0) },
            ListColumn(header: Messages.CLIExperience.labelSize.localized, priority: 3) { TextFormat.bytes($0["bytes"]) },
            ListColumn(header: Messages.CLIExperience.labelFile.localized) { Self.plain($0["filename"]) },
            ListColumn(header: Messages.CLIExperience.columnSource.localized, detailOnly: true) { item in
                item["managed"] == .null ? "" : Self.provider(item["managed"]["provider"]) + " · " + Self.plain(item["managed"]["projectID"])
            }
        ])
    }

    private var fileColumns: [ListColumn] {
        [ListColumn(header: Messages.CLIExperience.columnTitle.localized) { Self.plain($0["title"]) },
         ListColumn(header: Messages.CLIExperience.columnVersion.localized, priority: 1) { Self.plain($0["version"]) },
         ListColumn(header: Messages.CLIExperience.labelFile.localized) { Self.plain($0["filename"]) }]
    }

    func contentImport(_ value: Value) -> [String] {
        change(value, [(Messages.CLIExperience.labelFile.localized, Self.plain(value["file"])), (Messages.CLIExperience.labelKind.localized, Self.contentKind(value["kind"]))])
    }

    func contentChange(_ value: Value) -> [String] {
        change(value) + layout.table(fileColumns, value["files"].elements).lines
    }

    /// Files CurseForge only offers in a browser, and how to hand them over.
    func manualFiles(_ value: Value) -> [String] {
        let files = value.elements
        guard !files.isEmpty else { return [] }
        var lines = layout.prose(Messages.CLIExperience.manualDownloads.localized, style.warning)
        for file in files {
            lines += layout.fields([(Self.atom(file["fileID"]), Self.plain(file["filename"]))])
            lines += layout.paragraph(Self.plain(file["pageURL"]), indent: 4)
        }
        return lines
    }

    static func installAction(_ value: Value) -> String {
        let actions: [String: CatalogFileAction] = ["install": .install, "update": .update, "updateAndEnable": .updateAndEnable, "enable": .enable, "keep": .keep]
        return actions[value.string ?? ""]?.title ?? plain(value)
    }

    func contentInstall(_ value: Value) -> [String] {
        let project = value["project"]
        var lines = change(value, [(Messages.CLIExperience.labelProject.localized, Self.plain(project["title"]) + " (" + Self.plain(project["id"]) + ")"),
                                   (Messages.CLIExperience.labelVersion.localized, Self.plain(value["version"]["number"])),
                                   (Messages.CLIExperience.labelDownload.localized, TextFormat.bytes(value["downloadBytes"]))])
        lines += layout.table([ListColumn(header: Messages.CLIExperience.columnTitle.localized) { Self.plain($0["record"]["title"]) },
                               ListColumn(header: Messages.CLIExperience.columnVersion.localized, priority: 2) { Self.plain($0["record"]["version"]) },
                               ListColumn(header: Messages.CLIExperience.columnAction.localized, priority: 1) { Self.installAction($0["action"]) },
                               ListColumn(header: Messages.CLIExperience.labelFile.localized, detailOnly: true) { Self.plain($0["record"]["filename"]) }],
                              value["files"].elements).lines
        return lines + manualFiles(value["manualFiles"])
    }

    /// Available updates, or the updates applied, with any manual downloads.
    func contentUpdates(_ value: Value) -> [String] {
        let updates = value["updates"].elements
        if value["changed"] == .bool(false) || updates.isEmpty { return layout.prose(Messages.CLIExperience.upToDate.localized) }
        var lines: [String]
        if path.last == "update-check" { lines = layout.prose(Messages.CLIExperience.updatesAvailable(Int64(updates.count)).localized, style.bold) + layout.fields(targets()) }
        else { lines = change(value) }
        lines += layout.table(fileColumns, updates).lines
        lines += layout.fields([(Messages.CLIExperience.labelDownload.localized, TextFormat.bytes(value["downloadBytes"]))], indent: 0)
        lines += manualFiles(value["manualFiles"])
        if path.last == "update-check", let request {
            var words = ["content", "update"] + request.operands
            let files = request.options["file"]?.strings ?? []
            words += files.isEmpty ? ["--all"] : files.flatMap { ["--file", $0] }
            if let kind = request.string("kind") { words += ["--kind", kind] }
            lines.append(Messages.CLIExperience.nextAction(command(words)).localized)
        }
        return lines
    }

    // MARK: Modpacks

    /// An import, install or update: what the pack is, what it brings and what
    /// it changes, conflicts first.
    func packChange(_ value: Value) -> [String] {
        var rows = [(Messages.CLIExperience.labelModpack.localized, [value["name"], value["packVersion"]].map(Self.plain).filter { !$0.isEmpty }.joined(separator: " ")),
                    (Messages.CLIExperience.labelAuthor.localized, Self.plain(value["author"])),
                    (Messages.CLIExperience.labelGameVersion.localized, Self.plain(value["gameVersion"])),
                    (Messages.CLIExperience.labelFormat.localized, Self.plain(value["format"])),
                    (Messages.CLIExperience.labelContents.localized, TextFormat.contents(files: value["files"], bytes: value["bytes"])),
                    (Messages.CLIExperience.labelCurseForgeFiles.localized, (value["curseForgeFiles"].int ?? 0) > 0 ? Self.atom(value["curseForgeFiles"]) : ""),
                    (Messages.CLIExperience.labelJVMArguments.localized, Self.plain(value["jvmArguments"]))]
        if value["instance"] != .null {
            rows.insert((Messages.CLIExperience.labelNewInstance.localized, reference(value["instance"]["id"], in: index(.instance))), at: 0)
        }
        let changes = value["changes"].elements
        let counts = [ModpackFileChange.Action.add, .replace, .remove, .keep].compactMap { action -> String? in
            let count = changes.filter { $0["action"].string == action.rawValue }.count
            return count > 0 ? action.title + " " + String(count) : nil
        }
        rows.append((Messages.CLIExperience.labelChanges.localized, counts.joined(separator: " · ")))
        var lines = change(value, rows)
        if let summary = value["summary"].string, !summary.isEmpty { lines += layout.paragraph(Self.printable(summary), indent: 2) }
        if !changes.isEmpty {
            let conflicts = changes.filter { $0["conflict"] == .bool(true) }
            if !conflicts.isEmpty {
                lines += layout.prose(Messages.CLIExperience.conflicts.localized, style.warning)
                lines += layout.fields(conflicts.map { (Self.plain($0["path"]), Self.plain($0["explanation"])) })
            }
            if layout.details {
                lines += layout.table([ListColumn(header: Messages.CLIExperience.columnPath.localized) { Self.plain($0["path"]) },
                                       ListColumn(header: Messages.CLIExperience.columnAction.localized) { ModpackFileChange.Action(rawValue: $0["action"].string ?? "")?.title ?? Self.plain($0["action"]) }],
                                      changes).lines
            }
        }
        if value["complete"] == .bool(false) { lines += layout.prose(Messages.CLIExperience.previewIncomplete.localized, style.warning) }
        return lines + manualFiles(value["manualFiles"])
    }

    func pack(_ value: Value) -> [String] {
        let source = [Self.provider(value["provider"]), Self.plain(value["projectID"])].filter { !$0.isEmpty }.joined(separator: " · ")
        var rows = [(Messages.CLIExperience.labelInstance.localized, reference(value["instanceID"], in: index(.instance))),
                    (Messages.CLIExperience.labelFormat.localized, Self.plain(value["format"])), (Messages.CLIExperience.labelSource.localized, source),
                    (Messages.CLIExperience.labelManagedFiles.localized, Self.atom(value["managedFiles"]))]
        if layout.details { rows.append((Messages.CLIExperience.labelVersionID.localized, Self.plain(value["versionID"]))) }
        return layout.prose(Self.plain(value["name"]) + " " + Self.plain(value["version"]), style.bold) + layout.fields(rows)
    }

    func packReleases(_ value: Value) -> [String] {
        let current = value["current"], releases = value["releases"].elements
        var lines = layout.fields([(Messages.CLIExperience.labelInstalled.localized, Self.plain(current["name"]) + " " + Self.plain(current["version"]))], indent: 0)
        guard !releases.isEmpty else { return lines + layout.prose(Messages.CLIExperience.noReleases.localized) }
        let table = layout.table([
            ListColumn(header: Messages.CLIExperience.columnTitle.localized) { Self.plain($0["title"]) },
            ListColumn(header: Messages.CLIExperience.columnChannel.localized, priority: 1) { $0["stable"] == .bool(false) ? Messages.CLIExperience.prerelease.localized : Messages.CLIExperience.versionRelease.localized },
            ListColumn(header: Messages.CLIExperience.columnGameVersions.localized, priority: 2) { Self.abbreviated($0["gameVersions"].strings) },
            ListColumn(header: Messages.CLIExperience.columnPublished.localized, priority: 3) { TextFormat.date($0["publishedAt"]) },
            ListColumn(header: Messages.CLIExperience.columnID.localized) { Self.plain($0["id"]) }
        ], releases)
        lines += table.lines
        if table.hidden { lines += layout.paragraph(Messages.CLIExperience.hiddenColumns.localized).map(style.dim) }
        let manual = releases.filter { $0["manualDownloadRequired"] == .bool(true) }
        if !manual.isEmpty { lines += [""] + layout.prose(Messages.CLIExperience.manualRelease.localized, style.warning) + layout.bullets(manual.map { Self.plain($0["title"]) }) }
        return lines + pageFooter(value, count: releases.count)
    }

    func packRollback(_ value: Value) -> [String] {
        var lines = change(value)
        if let kept = value["preservedFiles"].int, kept > 0 { lines += layout.prose(Messages.CLIExperience.keptLocalFiles(Int64(kept)).localized) }
        return lines
    }

    func download(_ value: Value) -> [String] {
        change(value, [(Messages.CLIExperience.labelFile.localized, Self.plain(value["file"])),
                       (Messages.CLIExperience.labelVerified.localized, value["verified"] == .bool(true) ? Messages.CLIExperience.checksumMatches.localized : "")])
    }

    // MARK: Worlds

    static func gameMode(_ world: Value) -> String {
        if world["hardcore"] == .bool(true) { return Messages.CoreWorldManager.hardcoreMode.localized }
        return world["gameType"].int.flatMap { [0: Messages.CoreWorldManager.survivalMode, 1: Messages.CoreWorldManager.creativeMode,
                                                2: Messages.CoreWorldManager.adventureMode, 3: Messages.CoreWorldManager.spectatorMode][$0]?.localized } ?? ""
    }

    func worlds(_ value: Value) -> [String] {
        let items = value["items"].elements
        return page(value, items: items, columns: [
            ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) },
            ListColumn(header: Messages.CLIExperience.labelFolder.localized) { Self.plain($0["folder"]) },
            ListColumn(header: Messages.CLIExperience.labelMode.localized, priority: 3) { Self.gameMode($0) },
            ListColumn(header: Messages.CLIExperience.columnVersion.localized, priority: 2) { Self.plain($0["version"]) },
            ListColumn(header: Messages.CLIExperience.labelLastPlayed.localized, priority: 1) { TextFormat.date($0["lastPlayed"]) },
            ListColumn(header: Messages.CLIExperience.labelSize.localized, priority: 4) { TextFormat.bytes($0["bytes"]) }
        ], problems: items.compactMap { item in item["error"].string.map { (Self.plain(item["folder"]), Self.plain(.string($0))) } })
    }

    private func worldRows(_ world: Value) -> [(String, String)] {
        [(Messages.CLIExperience.labelFolder.localized, Self.plain(world["folder"])), (Messages.CLIExperience.labelMode.localized, Self.gameMode(world)),
         (Messages.CLIExperience.labelVersion.localized, Self.plain(world["version"])), (Messages.CLIExperience.labelLastPlayed.localized, TextFormat.date(world["lastPlayed"])),
         (Messages.CLIExperience.labelSize.localized, TextFormat.bytes(world["bytes"])),
         (Messages.CLIExperience.labelProblem.localized, world["error"].string.map { style.warning(Self.plain(.string($0))) } ?? "")]
    }

    func world(_ value: Value) -> [String] {
        layout.prose(Self.plain(value["name"]), style.bold) + layout.fields(worldRows(value))
    }

    func worldChange(_ value: Value) -> [String] {
        let world = value["world"]
        let name = world == .null ? Self.plain(value["folder"]) : Self.plain(world["name"]) + (world["name"] == world["folder"] ? "" : " (" + Self.plain(world["folder"]) + ")")
        return change(value, [(Messages.CLIExperience.labelWorld.localized, path.last == "import" && value["folder"] == .null ? "" : name),
                              (Messages.CLIExperience.labelFile.localized, Self.plain(value["file"]))])
    }

    private func backupRows(_ backup: Value) -> [(String, String)] {
        [(Messages.CLIExperience.labelBackup.localized, Self.plain(backup["id"])), (Messages.CLIExperience.labelWorld.localized, Self.plain(backup["worldName"] == .null ? backup["world"] : backup["worldName"])),
         (Messages.CLIExperience.labelCreated.localized, TextFormat.date(backup["createdAt"])), (Messages.CLIExperience.labelSize.localized, TextFormat.bytes(backup["bytes"]))]
    }

    func backups(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.labelWorld.localized) { Self.plain($0["worldName"] == .null ? $0["world"] : $0["worldName"]) },
            ListColumn(header: Messages.CLIExperience.labelCreated.localized, priority: 1) { TextFormat.date($0["createdAt"]) },
            ListColumn(header: Messages.CLIExperience.labelSize.localized, priority: 2) { TextFormat.bytes($0["bytes"]) },
            ListColumn(header: Messages.CLIExperience.labelBackup.localized) { Self.plain($0["id"]) }
        ])
    }

    func backupChange(_ value: Value) -> [String] {
        var rows: [(String, String)]
        if value["backup"] != .null { rows = backupRows(value["backup"]) }
        else if value["id"] != .null { rows = backupRows(value) }
        else if value["world"] != .null { rows = [(Messages.CLIExperience.labelWorld.localized, Self.plain(value["world"]["name"]))] }
        else { rows = [(Messages.CLIExperience.labelBackup.localized, Self.plain(value["removed"])), (Messages.CLIExperience.labelFolder.localized, Self.plain(value["folder"]))] }
        if value["replace"] == .bool(true) { rows.append((Messages.CLIExperience.labelReplace.localized, Self.yes(true))) }
        return change(value, rows)
    }

    // MARK: Data packs

    func dataPacks(_ value: Value) -> [String] {
        let items = value["items"].elements
        return page(value, items: items, columns: [
            ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["id"]) },
            ListColumn(header: Messages.CLIExperience.columnStatus.localized, priority: 1) { enabled($0) },
            ListColumn(header: Messages.CLIExperience.columnDescription.localized, priority: 2) { Self.plain($0["description"]) }
        ], problems: items.compactMap { item in item["error"].string.map { (Self.plain(item["id"]), Self.plain(.string($0))) } })
    }

    func dataPackOrder(_ value: Value) -> [String] {
        layout.prose(Messages.CLIExperience.dataPackPriority.localized, style.bold) + layout.fields(value["keys"].strings.enumerated().map { (String($0.offset + 1), $0.element) })
    }

    func dataPackChange(_ value: Value) -> [String] {
        change(value, [(Messages.CLIExperience.labelWorld.localized, Self.plain(value["world"])), (Messages.CLIExperience.labelDataPack.localized, Self.plain(value["name"]))])
            + layout.prose(Messages.CLIExperience.nextWorldLoad.localized, style.dim)
    }

    func dataPackInstall(_ value: Value) -> [String] {
        change(value, [(Messages.CLIExperience.labelWorld.localized, request?.operands[safe: 1] ?? ""), (Messages.CLIExperience.labelDownload.localized, TextFormat.bytes(value["downloadBytes"]))])
            + layout.table([ListColumn(header: Messages.CLIExperience.columnName.localized) { Self.plain($0["name"]) },
                            ListColumn(header: Messages.CLIExperience.columnVersion.localized) { Self.plain($0["number"]) }], value["versions"].elements).lines
            + layout.prose(Messages.CLIExperience.nextWorldLoad.localized, style.dim)
    }

    // MARK: Schematics

    func schematics(_ value: Value) -> [String] {
        page(value, items: value["items"].elements, columns: [
            ListColumn(header: Messages.CLIExperience.columnPath.localized) { Self.plain($0["path"]) + ($0["directory"] == .bool(true) ? "/" : "") },
            ListColumn(header: Messages.CLIExperience.labelSize.localized, priority: 2) { $0["directory"] == .bool(true) ? "" : TextFormat.bytes($0["bytes"]) },
            ListColumn(header: Messages.CLIExperience.labelModified.localized, priority: 1) { TextFormat.date($0["modifiedAt"]) }
        ])
    }

    func schematic(_ value: Value) -> [String] {
        let entry = value["entry"], dimensions = value["dimensions"].elements.map(Self.atom).joined(separator: " × ")
        var lines = layout.prose(Self.plain(value["name"] == .null ? entry["path"] : value["name"]), style.bold)
        var rows = [(Messages.CLIExperience.labelAuthor.localized, Self.plain(value["author"])), (Messages.CLIExperience.labelDimensions.localized, dimensions),
                    (Messages.CLIExperience.labelBlocks.localized, value["blocks"] == .null ? "" : Self.atom(value["blocks"])),
                    (Messages.CLIExperience.labelRegions.localized, value["regions"] == .null ? "" : Self.atom(value["regions"])),
                    (Messages.CLIExperience.labelFile.localized, Self.plain(entry["path"])), (Messages.CLIExperience.labelSize.localized, TextFormat.bytes(entry["bytes"])),
                    (Messages.CLIExperience.labelModified.localized, TextFormat.date(entry["modifiedAt"]))]
        if layout.details {
            rows += [(Messages.CLIExperience.labelFormatVersion.localized, value["formatVersion"] == .null ? "" : Self.atom(value["formatVersion"])),
                     (Messages.CLIExperience.labelDataVersion.localized, value["gameDataVersion"] == .null ? "" : Self.atom(value["gameDataVersion"]))]
        }
        lines += layout.fields(rows)
        if let description = value["description"].string, !description.isEmpty { lines += [""] + layout.paragraph(Self.printable(description), indent: 2) }
        return lines
    }

    func schematicChange(_ value: Value) -> [String] {
        if value["entry"] != .null {
            return change(value, [(Messages.CLIExperience.labelSchematic.localized, Self.plain(value["entry"]["path"])), (Messages.CLIExperience.labelFile.localized, Self.plain(value["file"]))])
        }
        return change(value, [(path.last == "import" ? Messages.CLIExperience.labelFile.localized : Messages.CLIExperience.labelName.localized, Self.plain(value["target"])),
                              (Messages.CLIExperience.labelFolder.localized, Self.plain(value["directory"]))])
    }
}
