import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageInstanceMoves(_ args: [String], paths: LauncherPaths) async throws {
        let service = InstanceMover(paths: paths)
        if args.first == "move-instance" {
            let usage = Messages.CLIInstanceMoves.usageText1.localized
            guard (3...4).contains(args.count), let id = UUID(uuidString: args[1]),
                  let directory = args[2] == "default" ? GameDirectory.defaultID : UUID(uuidString: args[2]),
                  args.count == 3 || args[3] == "--apply" else { throw RuriError.message(usage) }
            let preview = try await service.preview(instanceID: id, directoryID: directory)
            print(Messages.CLIInstanceMoves.previewText1(String(describing: preview.source.name), String(describing: preview.source.id), String(describing: preview.sourceDirectory.path), String(describing: preview.destination.path), Int64(preview.fileCount), String(describing: preview.bytes)).localized)
            if let kept = preview.retainedGameDirectory { print(Messages.CLIInstanceMoves.keptText1(String(describing: kept.path)).localized) }
            if preview.source.runDirectory == .shared { print(Messages.CLIInstanceMoves.keptText2.localized) }
            if let prior = preview.preservedPreviousData { print(Messages.CLIInstanceMoves.priorText1(String(describing: prior.path)).localized) }
            if args.count == 4 {
                do { printMoveResult(try await service.move(preview, progress: printMoveProgress)) }
                catch let failure as InstanceMoveFailure {
                    for url in failure.preservedFiles { print(Messages.CLIInstanceMoves.failureText1(String(describing: url.path)).localized) }
                    throw failure
                }
            }
        } else {
            let usage = Messages.CLIInstanceMoves.usageText2.localized
            guard (2...4).contains(args.count), let id = UUID(uuidString: args[1]) else { throw RuriError.message(usage) }
            let flags = Array(args.dropFirst(2))
            guard flags.allSatisfy({ ["--apply", "--keep-source"].contains($0) }), Set(flags).count == flags.count,
                  !flags.contains("--keep-source") || flags.contains("--apply") else { throw RuriError.message(usage) }
            guard let pending = try await service.pending(instanceID: id) else { print(Messages.CLIInstanceMoves.pendingText1.localized); return }
            print(Messages.CLIInstanceMoves.pendingText4(String(describing: pending.instance.name), String(describing: pending.id), String(describing: pending.committed ? Messages.CLIInstanceMoves.pendingText2.localized : Messages.CLIInstanceMoves.pendingText3.localized), String(describing: pending.source.path), String(describing: pending.destination.path), String(describing: pending.workspace.path)).localized)
            if let retired = pending.retiredSource { print(Messages.CLIInstanceMoves.retiredText1(String(describing: retired.path)).localized) }
            if flags.contains("--apply") {
                guard pending.committed || !flags.contains("--keep-source") else { throw RuriError.message(Messages.CLIInstanceMoves.retiredText2) }
                printMoveResult(try await service.recover(instanceID: id, transactionID: pending.id, preservingSource: flags.contains("--keep-source"), progress: printMoveProgress))
            }
        }
    }
    private static func printMoveProgress(_ value: InstanceMoveProgress) {
        try? FileHandle.standardOutput.write(contentsOf: Data("\(value.phase.rawValue) · \(value.bytesCopied)/\(value.totalBytes) bytes\n".utf8))
    }
    private static func printMoveResult(_ result: InstanceMoveResult) {
        print(result.warning ?? Messages.CLIInstanceMoves.printMoveResultText1.localized)
        for url in result.preservedFiles { print(Messages.CLIInstanceMoves.failureText1(String(describing: url.path)).localized) }
    }
}
