import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageInstanceMoves(_ args: [String], paths: LauncherPaths) async throws {
        let service = InstanceMover(paths: paths)
        if args.first == "move-instance" {
            let usage = Messages.CLIInstanceMoves.moveInstanceUsage.localized
            guard (3...4).contains(args.count), let id = UUID(uuidString: args[1]),
                  let directory = args[2] == "default" ? GameDirectory.defaultID : UUID(uuidString: args[2]),
                  args.count == 3 || args[3] == "--apply" else { throw RuriError.message(usage) }
            let preview = try await service.preview(instanceID: id, directoryID: directory)
            print(Messages.CLIInstanceMoves.moveInstancePreview(preview.source.name, String(describing: preview.source.id), preview.sourceDirectory.path, preview.destination.path, Int64(preview.fileCount), String(describing: preview.bytes)).localized)
            if let kept = preview.retainedGameDirectory { print(Messages.CLIInstanceMoves.originalRunDirectoryRetained(kept.path).localized) }
            if preview.source.runDirectory == .shared { print(Messages.CLIInstanceMoves.sharedContentCopy.localized) }
            if let prior = preview.preservedPreviousData { print(Messages.CLIInstanceMoves.priorDirectoryContents(prior.path).localized) }
            if args.count == 4 {
                do { printMoveResult(try await service.move(preview, progress: printMoveProgress)) }
                catch let failure as InstanceMoveFailure {
                    for url in failure.preservedFiles { print(Messages.CLIInstanceMoves.retainedFiles(url.path).localized) }
                    throw failure
                }
            }
        } else {
            let usage = Messages.CLIInstanceMoves.recoverMoveUsage.localized
            guard (2...4).contains(args.count), let id = UUID(uuidString: args[1]) else { throw RuriError.message(usage) }
            let flags = Array(args.dropFirst(2))
            guard flags.allSatisfy({ ["--apply", "--keep-source"].contains($0) }), Set(flags).count == flags.count,
                  !flags.contains("--keep-source") || flags.contains("--apply") else { throw RuriError.message(usage) }
            guard let pending = try await service.pending(instanceID: id) else { print(Messages.CLIInstanceMoves.noPendingMove.localized); return }
            print(Messages.CLIInstanceMoves.moveDetails(pending.instance.name, String(describing: pending.id), String(describing: pending.committed ? Messages.CLIInstanceMoves.moveCommitted.localized : Messages.CLIInstanceMoves.moveIncomplete.localized), pending.source.path, pending.destination.path, pending.workspace.path).localized)
            if let retired = pending.retiredSource { print(Messages.CLIInstanceMoves.retiredFiles(retired.path).localized) }
            if flags.contains("--apply") {
                guard pending.committed || !flags.contains("--keep-source") else { throw RuriError.message(Messages.CLIInstanceMoves.moveRecoveryRetainsSource) }
                printMoveResult(try await service.recover(instanceID: id, transactionID: pending.id, preservingSource: flags.contains("--keep-source"), progress: printMoveProgress))
            }
        }
    }
    private static func printMoveProgress(_ value: InstanceMoveProgress) {
        try? FileHandle.standardOutput.write(contentsOf: Data("\(value.phase.rawValue) · \(value.bytesCopied)/\(value.totalBytes) bytes\n".utf8))
    }
    private static func printMoveResult(_ result: InstanceMoveResult) {
        print(result.warning ?? Messages.CLIInstanceMoves.moveCompleted.localized)
        for url in result.preservedFiles { print(Messages.CLIInstanceMoves.retainedFiles(url.path).localized) }
    }
}
