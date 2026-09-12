import RuriLocalization
import Foundation
import Darwin

enum RunDirectoryFileCopy {
    /// APFS clones are independent files, not hard links. Other filesystems
    /// fall back to bounded chunks so cancellation can interrupt a large file.
    static func file(_ source: URL, to target: URL, preferClone: Bool = true, stabilizeIdentity: Bool = false, created: () throws -> Void = {}, validate: () throws -> Void = {}, progress: (Int64) -> Void) throws {
        let inputFD = open(source.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard inputFD >= 0 else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.inputFDText1(String(describing: source.lastPathComponent))) }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true); defer { try? input.close() }
        var info = stat()
        guard fstat(inputFD, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.infoText1) }
        try Task.checkCancellation()
        if preferClone, fclonefileat(inputFD, AT_FDCWD, target.path, UInt32(CLONE_NOOWNERCOPY | CLONE_ACL)) == 0 { progress(info.st_size); return }
        let outputFD = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard outputFD >= 0 else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.outputFDText1(String(describing: target.lastPathComponent))) }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true); defer { try? output.close() }
        // ExFAT replaces the temporary inode of an empty file when allocating
        // its first cluster. Reserve that cluster before journaling ownership.
        // The one-byte zero placeholder is overwritten by the normal copy.
        if stabilizeIdentity && info.st_size > 0 {
            guard ftruncate(outputFD, 1) == 0 else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.outputText1) }
            try output.synchronize()
        }
        try created()
        var copied: Int64 = 0
        while copied < info.st_size {
            try Task.checkCancellation()
            try validate()
            let bytes = try input.read(upToCount: Int(min(1_048_576, info.st_size - copied))) ?? Data()
            guard !bytes.isEmpty else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.bytesText1) }
            try output.write(contentsOf: bytes); copied += Int64(bytes.count); progress(Int64(bytes.count))
        }
        try output.synchronize()
        try validate()
        try FileExtendedAttributes.copy(from: inputFD, to: outputFD)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        try FileManager.default.setAttributes([.posixPermissions: info.st_mode & 0o777, .modificationDate: attributes[.modificationDate] ?? Date()], ofItemAtPath: target.path)
    }
    static func entries(_ entries: [FileTree.Entry], to root: URL, validate: () throws -> Void, progress: (Int64, Bool) -> Void) throws {
        try validate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for entry in entries {
            try Task.checkCancellation()
            try validate()
            let target = try LauncherPaths.safePath(entry.path, within: root)
            if entry.directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file(entry.url, to: target) { progress($0, false) }
                progress(0, true)
            }
        }
        for entry in entries.reversed() where entry.directory {
            try validate()
            let target = try LauncherPaths.safePath(entry.path, within: root)
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.url.path)
            try FileExtendedAttributes.copy(from: entry.url, to: target)
            try FileManager.default.setAttributes([.posixPermissions: attributes[.posixPermissions] ?? 0o755, .modificationDate: entry.modified], ofItemAtPath: target.path)
        }
    }
    static func moveWithoutReplacing(_ source: URL, to target: URL) throws {
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.moveWithoutReplacingText1(String(describing: target.lastPathComponent))) }
    }

    /// Some removable filesystems (including macOS ExFAT) do not implement
    /// RENAME_EXCL. Claim an empty destination exclusively, record its identity,
    /// then copy into it while retaining the complete staged original.
    static func publish(_ source: URL, to target: URL, directory: Bool, excluding: Set<String> = [], ignoringTransientFiles: Bool = true, created: (RunDirectoryCopyJournal.Identity) throws -> Void, validate: () throws -> Void, progress: (Int64) -> Void) throws {
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 { return }
        guard errno == ENOTSUP else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.publishText1(String(describing: target.lastPathComponent))) }
        try copyForPublication(source, to: target, directory: directory, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles, created: created, validate: validate, progress: progress)
    }

    static func copyForPublication(_ source: URL, to target: URL, directory: Bool, excluding: Set<String> = [], ignoringTransientFiles: Bool = true, created: (RunDirectoryCopyJournal.Identity) throws -> Void, validate: () throws -> Void, progress: (Int64) -> Void) throws {
        var identity: RunDirectoryCopyJournal.Identity?
        func record() throws {
            let value = try RunDirectoryCopyJournal.Identity.read(target)
            identity = value; try created(value)
        }
        func check() throws {
            try validate()
            guard identity?.matches(target) == true else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.checkText1) }
        }
        try validate(); try Task.checkCancellation()
        if directory {
            guard mkdir(target.path, S_IRWXU) == 0 else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.checkText2(String(describing: target.lastPathComponent))) }
            try record()
            try entries(FileTree.entries(in: source, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles), to: target, validate: check) { amount, _ in progress(amount) }
            try check()
            let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
            try FileExtendedAttributes.copy(from: source, to: target)
            try FileManager.default.setAttributes([.posixPermissions: attributes[.posixPermissions] ?? 0o755, .modificationDate: attributes[.modificationDate] ?? Date()], ofItemAtPath: target.path)
        } else {
            try file(source, to: target, preferClone: false, stabilizeIdentity: true, created: record, validate: check, progress: progress)
        }
    }

    /// The destination is inside a newly, exclusively created private directory.
    /// A plain rename is safe here even on volumes without exclusive rename;
    /// no existing destination item is ever used or replaced.
    static func returnToWorkspace(_ source: URL, workspace: URL) throws {
        let parent = try LauncherPaths.safePath("returned", within: workspace)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let unique = parent.appendingPathComponent(UUID().uuidString)
        guard mkdir(unique.path, S_IRWXU) == 0 else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.uniqueText1) }
        guard rename(source.path, unique.appendingPathComponent(source.lastPathComponent).path) == 0 else { throw RuriError.message(Messages.CoreRunDirectoryFileCopy.uniqueText2) }
    }
}
