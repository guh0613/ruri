import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageSchematics(_ args: [String], paths: LauncherPaths) async throws {
        let usage = Messages.CLISchematicCommands.schematicUsage.localized
        guard args.count >= 2, let id = UUID(uuidString: args[1]), try StateStore.load(paths).instances.contains(where: { $0.id == id }) else { throw RuriError.message(usage) }
        let manager = SchematicManager(paths: paths, instanceID: id)
        let arguments = args.filter { $0 != "--apply" }, apply = args.last == "--apply"
        let action = arguments.count > 2 ? arguments[2] : "list"
        guard !args.contains("--apply") || apply else { throw RuriError.message(usage) }
        if action == "list" {
            guard arguments.count <= 4 else { throw RuriError.message(usage) }
            for item in try await manager.list(directory: arguments.count == 4 ? arguments[3] : "") {
                print("\(item.isDirectory ? "[folder]" : "[file]") \(item.id)\(item.isDirectory ? "" : "  \(item.size) bytes")")
            }
            return
        }
        guard ["info", "import", "mkdir", "export", "remove"].contains(action), arguments.count >= 4 else { throw RuriError.message(usage) }
        if action == "info" || action == "remove" { guard arguments.count == 4 else { throw RuriError.message(usage) } }
        else if action == "export" { guard arguments.count == 5 else { throw RuriError.message(usage) } }
        else { guard arguments.count <= 5 else { throw RuriError.message(usage) } }
        let lease = try apply ? GameRunLease.acquire(paths: paths, instanceID: id) : nil
        defer { withExtendedLifetime(lease) {} }
        if action == "import" || action == "mkdir" {
            print(Messages.CLISchematicCommands.schematicInstalled(String(describing: action), String(describing: arguments[3]), String(describing: arguments.count == 5 ? arguments[4] : "")).localized)
            if apply {
                if action == "import" { try await manager.importFiles([URL(fileURLWithPath: arguments[3])], directory: arguments.count == 5 ? arguments[4] : "") }
                else { try await manager.createFolder(arguments[3], directory: arguments.count == 5 ? arguments[4] : "") }
            }
            return
        }
        let components = arguments[3].split(separator: "/", omittingEmptySubsequences: false)
        let directory = components.dropLast().joined(separator: "/")
        guard let entry = try await manager.list(directory: directory).first(where: { $0.id == arguments[3] }) else { throw RuriError.message(Messages.CLISchematicCommands.schematicNotFound) }
        if action == "info" {
            let info = try await manager.info(entry)
            print(info.name ?? entry.name)
            if let author = info.author { print(Messages.CLISchematicCommands.schematicAuthor(String(describing: author)).localized) }
            if let description = info.description { print(description) }
            if !info.dimensions.isEmpty { print(Messages.CLISchematicCommands.schematicSize(String(describing: info.dimensions.map(String.init).joined(separator: " × "))).localized) }
            if let blocks = info.blocks { print(Messages.CLISchematicCommands.schematicBlocks(String(describing: blocks)).localized) }
            if let regions = info.regions { print(Messages.CLISchematicCommands.schematicRegions(String(describing: regions)).localized) }
            if let version = info.formatVersion { print(Messages.CLISchematicCommands.schematicFormatVersion(String(describing: version)).localized) }
            if let version = info.gameDataVersion { print(Messages.CLISchematicCommands.schematicGameDataVersion(String(describing: version)).localized) }
        } else {
            print("\(action)：\(entry.id)")
            if apply {
                if action == "export" { try await manager.export(entry, to: URL(fileURLWithPath: arguments[4])) }
                else if let trash = try await manager.remove(entry) { print(Messages.CLISchematicCommands.schematicTrashed(trash.path).localized) }
            }
        }
    }
}
