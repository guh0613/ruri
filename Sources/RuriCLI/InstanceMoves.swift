import Foundation
import RuriCore

extension CLI {
    static func manageInstanceMoves(_ args: [String], paths: LauncherPaths) async throws {
        let service = InstanceMover(paths: paths)
        if args.first == "move-instance" {
            let usage = "用法：ruri-cli move-instance <实例UUID> <目标文件夹UUID|default> [--apply]。默认预览；--apply 移动并在校验后清理原实例文件。"
            guard (3...4).contains(args.count), let id = UUID(uuidString: args[1]),
                  let directory = args[2] == "default" ? GameDirectory.defaultID : UUID(uuidString: args[2]),
                  args.count == 3 || args[3] == "--apply" else { throw RuriError.message(usage) }
            let preview = try await service.preview(instanceID: id, directoryID: directory)
            print("\(preview.source.name) · \(preview.source.id)\n原位置：\(preview.sourceDirectory.path)\n目标位置：\(preview.destination.path)\n\(preview.fileCount) 个文件，\(preview.bytes) 字节\n实例身份、设置和运行历史保留。")
            if let kept = preview.retainedGameDirectory { print("原运行目录保留：\(kept.path)") }
            if preview.source.runDirectory == .shared { print("目标使用当前共享游戏内容的独立副本。") }
            if let prior = preview.preservedPreviousData { print("旧的独立目录内容会保留在：\(prior.path)") }
            if args.count == 4 {
                do { printMoveResult(try await service.move(preview, progress: printMoveProgress)) }
                catch let failure as InstanceMoveFailure {
                    for url in failure.preservedFiles { print("保留文件：\(url.path)") }
                    throw failure
                }
            }
        } else {
            let usage = "用法：ruri-cli recover-instance-move <实例UUID> [--apply] [--keep-source]。默认查看；--apply 恢复，--keep-source 保留已提交移动的原文件。"
            guard (2...4).contains(args.count), let id = UUID(uuidString: args[1]) else { throw RuriError.message(usage) }
            let flags = Array(args.dropFirst(2))
            guard flags.allSatisfy({ ["--apply", "--keep-source"].contains($0) }), Set(flags).count == flags.count,
                  !flags.contains("--keep-source") || flags.contains("--apply") else { throw RuriError.message(usage) }
            guard let pending = try await service.pending(instanceID: id) else { print("没有待恢复的实例移动。"); return }
            print("\(pending.instance.name) · \(pending.id)\n\(pending.committed ? "实例已移动，等待校验与清理" : "移动尚未提交，原实例保留")\n原位置：\(pending.source.path)\n目标位置：\(pending.destination.path)\n工作区：\(pending.workspace.path)")
            if let retired = pending.retiredSource { print("待清理的原文件：\(retired.path)") }
            if flags.contains("--apply") {
                guard pending.committed || !flags.contains("--keep-source") else { throw RuriError.message("移动尚未提交，恢复默认保留原实例，无需 --keep-source。") }
                printMoveResult(try await service.recover(instanceID: id, transactionID: pending.id, preservingSource: flags.contains("--keep-source"), progress: printMoveProgress))
            }
        }
    }
    private static func printMoveProgress(_ value: InstanceMoveProgress) {
        try? FileHandle.standardOutput.write(contentsOf: Data("\(value.phase.rawValue) · \(value.bytesCopied)/\(value.totalBytes) bytes\n".utf8))
    }
    private static func printMoveResult(_ result: InstanceMoveResult) {
        print(result.warning ?? "实例移动已完成，已校验并清理原实例文件。")
        for url in result.preservedFiles { print("保留文件：\(url.path)") }
    }
}
