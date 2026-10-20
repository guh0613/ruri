import Foundation
import RuriCore
import RuriLocalization

/// Recovery, health checks, the app, the command line tool, the cache and schemas.
extension CommandTextRenderer {
    // MARK: Recovery

    private static func recoveryStatus(_ value: Value) -> String? {
        let statuses: [GameSessionRecovery.Status] = [.finished, .monitoring, .monitorUnconfirmed, .gameRunning, .commandRunning, .processEnded, .confirmationRequired]
        return statuses.first { String(describing: $0) == value.string }?.title
    }

    /// Each unfinished operation with what it concerns and the command that recovers it.
    func recoveryItems(_ value: Value) -> [String] {
        let items = value["items"].elements, issues = value["issues"].elements
        let instances = index(.instance), directories = index(.directory)
        var lines: [String] = items.isEmpty && issues.isEmpty ? layout.prose(Messages.CLIExperience.nothingToRecover.localized) : []
        for (offset, item) in items.enumerated() {
            let target = reference(item["target"], in: item["kind"].string == "repository-import" ? directories : instances)
            lines += (offset == 0 ? [] : [""]) + layout.prose(Self.plain(item["kind"]) + " · " + target, style.bold)
            var rows: [(String, String)] = []
            if item["explanation"] != .null { rows.append((Messages.CLIExperience.labelStatus.localized, [Self.recoveryStatus(item["status"]), item["explanation"].string].compactMap { $0 }.joined(separator: " "))) }
            if let committed = item["committed"].bool { rows.append((Messages.CLIExperience.labelApplied.localized, Self.yes(committed))) }
            rows.append((Messages.CLIExperience.labelName.localized, Self.plain(item["name"])))
            if let finish = item["canFinish"].bool { rows.append((Messages.CLIExperience.labelCanFinish.localized, Self.yes(finish))) }
            rows.append((Messages.CLIExperience.labelWorkspace.localized, Self.plain(item["workspace"])))
            if layout.details { rows.append((Messages.CLIExperience.labelTransaction.localized, Self.plain(item["transaction"]))) }
            lines += layout.fields(rows)
            if let words = try? item["nextAction"].decode([String].self) { lines.append(Messages.CLIExperience.nextAction(command(words)).localized) }
        }
        if !issues.isEmpty {
            lines += (lines.isEmpty ? [] : [""]) + layout.prose(Messages.CLIExperience.couldNotCheck.localized, style.warning)
            lines += layout.fields(issues.map { issue in
                (issue["directoryID"] != .null ? reference(issue["directoryID"], in: directories) : reference(issue["instanceID"], in: instances), Self.plain(issue["error"]))
            })
        }
        return lines + (items.isEmpty ? [] : pageFooter(value, count: items.count))
    }

    func recovery(_ value: Value) -> [String] {
        if value["state"] != .null { return outcome(value) + session(value) }
        return change(value, [(Messages.CLIExperience.labelKind.localized, Self.plain(value["kind"]))])
    }

    // MARK: Health

    /// Every check, problems first, each named by what it checked and marked
    /// in words as well as color.
    func checks(_ report: Value) -> [String] {
        let instances = index(.instance), accounts = index(.account), directories = index(.directory)
        func title(_ check: Value) -> String {
            let details = check["details"]
            switch check["check"].string {
            case "state"?: return Messages.CLIExperience.checkState.localized
            case "directory"?: return Messages.CLIExperience.checkDirectory(reference(details["id"], in: directories)).localized
            case "monitor"?: return Messages.CLIExperience.checkMonitor.localized
            case "gameHost"?: return Messages.CLIExperience.checkGameHost.localized
            case "credentials"?: return Messages.CLIExperience.checkCredentials(reference(details["accountID"], in: accounts)).localized
            case "instance"?: return Messages.CLIExperience.checkInstance(reference(details["id"], in: instances)).localized
            default: return Self.plain(check["check"])
            }
        }
        func passed(_ check: Value) -> [String] {
            let java = check["details"]["java"]
            var parts = ["✓ " + title(check)]
            if java != .null { parts.append([Messages.CLIExperience.labelJava.localized, Self.atom(java["major"])].joined(separator: " ")) }
            if java != .null && layout.details { parts.append(Self.plain(java["path"])) }
            return layout.paragraph(parts.joined(separator: " · "), indent: 2).map(style.good)
        }
        func failed(_ check: Value) -> [String] {
            let details = check["details"], problem: String
            switch (check["check"].string, details["availability"].string) {
            case ("credentials"?, "missing"?): problem = Messages.CLIExperience.credentialsMissing.localized
            case ("credentials"?, _): problem = Messages.CLIExperience.credentialsUnavailable.localized
            case ("directory"?, _): problem = [Messages.CLIExperience.statusUnavailable.localized, Self.plain(details["path"])].joined(separator: " · ")
            case ("monitor"?, _), ("gameHost"?, _): problem = Messages.CLIExperience.notFound.localized
            default: problem = Self.plain(details["message"])
            }
            return layout.paragraph("✗ " + title(check), indent: 2).map(style.bad) + layout.paragraph(problem, indent: 4)
        }
        let checks = report["checks"].elements
        return checks.filter { $0["ok"] != .bool(true) }.flatMap(failed) + checks.filter { $0["ok"] == .bool(true) }.flatMap(passed)
    }

    func doctor(_ value: Value) -> [String] {
        layout.prose(Messages.CLIExperience.allChecksPassed.localized, style.good) + checks(value)
    }

    // MARK: App and command line tool

    func appInfo(_ value: Value) -> [String] {
        var rows = [(Messages.CLIExperience.labelVersion.localized, Self.plain(value["version"])),
                    (Messages.CLIExperience.labelApplication.localized, value["application"].string ?? Messages.CLIExperience.notFound.localized),
                    (Messages.CLIExperience.labelCommand.localized, Self.plain(value["cli"])),
                    (Messages.CLIExperience.labelDataDirectory.localized, Self.plain(value["dataDirectory"]))]
        if layout.details { rows.append((Messages.CLIExperience.labelSchemaVersion.localized, Self.atom(value["schemaVersion"]))) }
        return layout.fields(rows, indent: 0)
    }

    func language(_ value: Value) -> [String] {
        layout.fields([(Messages.CLIExperience.labelLanguage.localized, Self.plain(value["language"])),
                       (Messages.CLIExperience.labelSupported.localized, (["system"] + value["supported"].strings).joined(separator: ", "))], indent: 0)
    }

    /// Whether `ruri` reaches this copy of Ruri, and what to do when it does not.
    func cliStatus(_ status: Value, headline: Bool = true) -> [String] {
        let installed = status["installed"] == .bool(true), link = Self.plain(status["link"])
        var lines: [String] = []
        if headline {
            if installed { lines += layout.prose(Messages.CLIExperience.cliInstalled(TextLayout.unbroken(link)).localized, style.good) }
            else if status["target"] != .null && status["owned"] == .bool(true) { lines += layout.prose(Messages.CLIExperience.cliOtherCopy(TextLayout.unbroken(link)).localized, style.warning) }
            else { lines += layout.prose(Messages.CLIExperience.cliNotInstalled.localized, style.bold) }
        }
        lines += layout.fields([(Messages.CLIExperience.labelLink.localized, link), (Messages.CLIExperience.labelPointsTo.localized, Self.plain(status["target"])),
                                (Messages.CLIExperience.labelExecutable.localized, Self.plain(status["executable"])),
                                (Messages.CLIExperience.labelInPath.localized, status["onPath"] == .bool(true) ? Self.yes(true) : style.warning(Self.yes(false))),
                                (Messages.CLIExperience.labelPackageManager.localized, Self.plain(status["packageManager"])),
                                (Messages.CLIExperience.labelOldLink.localized, Self.plain(status["legacyLink"]))])
        if installed && status["onPath"] == .bool(false) {
            lines += layout.prose(Messages.CLIExperience.cliNotInPath(TextLayout.unbroken((link as NSString).deletingLastPathComponent)).localized, style.warning)
        }
        if headline && !installed && status["packageManager"] == .null {
            if status["requiresAuthorization"] == .bool(true) { lines += layout.prose(Messages.CLISetup.authorizationRequired.localized, style.dim) }
            else { lines.append(Messages.CLIExperience.nextAction(command(["cli", "install"])).localized) }
        }
        return lines
    }

    func cliChange(_ value: Value) -> [String] {
        let headline: [String]
        if value["changed"] == .bool(false) {
            headline = layout.prose(path.last == "install" ? Messages.CLIExperience.cliAlreadyInstalled.localized : Messages.CLIExperience.cliNothingToRemove.localized, style.bold)
        } else { headline = outcome(value) }
        return headline + cliStatus(value["status"], headline: false)
    }

    func cache(_ value: Value) -> [String] {
        let size = TextFormat.contents(files: value["files"], bytes: value["bytes"])
        if path.last == "status" {
            guard (value["files"].int ?? 0) > 0 else { return layout.prose(Messages.CLIExperience.cacheEmpty.localized) }
            return layout.prose(Messages.CLIExperience.cacheReclaimable(TextFormat.bytes(value["bytes"]), Messages.CLIExperience.fileCount(Int64(value["files"].int ?? 0)).localized).localized)
        }
        let label = value["dryRun"] == .bool(true) ? Messages.CLIExperience.labelFrees.localized : Messages.CLIExperience.labelFreed.localized
        return change(value, [(label, size)])
    }

    // MARK: Schemas

    /// A command index, or each command with its traits and its schemas as JSON.
    func schema(_ value: Value) -> [String] {
        let commands = value["commands"].elements
        var lines: [String] = []
        if commands.allSatisfy({ $0["usage"].string != nil }) && value["configuration"] == .null && value["patchSchemas"] == .null {
            for command in commands { lines += [Self.plain(command["usage"])] + layout.paragraph(Self.plain(command["summary"]), indent: 4) }
            return lines
        }
        for command in commands {
            if !lines.isEmpty { lines.append("") }
            lines += layout.prose(Self.shell(["ruri"] + command["path"].strings), style.bold)
            if command["summary"] != .null {
                lines += layout.paragraph(Self.plain(command["summary"]))
                lines += layout.fields([(Messages.CLIExperience.labelChangesData.localized, Self.yes(command["mutation"] == .bool(true))),
                                        (Messages.CLIExperience.labelDryRun.localized, Self.yes(command["supportsDryRun"] == .bool(true))),
                                        (Messages.CLIExperience.labelNeedsConfirmation.localized, Self.yes(command["confirmation"] == .bool(true))),
                                        (Messages.CLIExperience.labelNeedsYou.localized, Self.yes(command["userParticipation"] == .bool(true)))])
            }
            for (key, title) in [("inputSchema", Messages.CLIExperience.sectionInputSchema.localized), ("resultSchema", Messages.CLIExperience.sectionResultSchema.localized)] where command[key] != .null {
                lines += [style.bold(title)] + Self.json(command[key])
            }
        }
        for (key, title) in [("configuration", Messages.CLIExperience.sectionConfigurationFields.localized), ("patchSchemas", Messages.CLIExperience.sectionPatchSchemas.localized)] where value[key] != .null {
            lines += ["", style.bold(title)] + Self.json(value[key])
        }
        return lines
    }

    /// Indented JSON, for values that only JSON describes exactly.
    static func json(_ value: Value) -> [String] {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(value), as: UTF8.self).components(separatedBy: "\n")) ?? []
    }
}
