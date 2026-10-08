import Foundation
import Darwin

/// Frees the space the launcher cache holds on its own. On APFS a cached
/// download and the game files made from it are clones, so entries that game
/// files still share cost nothing and stay for later installs.
public struct CacheMaintenance: Sendable {
    public struct Summary: Sendable, Equatable {
        /// Space the removals return to the volume.
        public let bytes: Int64
        public let files: Int
    }
    /// Download destinations. Files here are only needed until installed.
    static let stores = ["objects", "curseforge", "modrinth", "datapacks", "pack-updates", "installers"]
    /// Folders an operation removes when it ends; one left behind was interrupted.
    static let workspacePrefixes = ["transfer-", "export-mrpack-", "export-mcbbs-", "complete-export-", "catalog-enable-", "optifine-combined-"]
    static let workspaceFolders = ["loader-work", "optifine-work"]
    static let partials = ".ruri-partials"

    let cache: URL
    let now: Date
    /// A file changed this recently may belong to an operation in another process.
    let recent: TimeInterval
    /// Interrupted work stays this long so a download can still resume.
    let stale: TimeInterval

    public init(paths: LauncherPaths) { self.init(cache: paths.cache) }
    init(cache: URL, now: Date = Date(), recent: TimeInterval = 3600, stale: TimeInterval = 86_400) {
        self.cache = cache.standardizedFileURL; self.now = now; self.recent = recent; self.stale = stale
    }

    public func survey() -> Summary { plan().summary }

    @discardableResult public func clean() -> Summary {
        let plan = plan()
        for url in plan.removals { try? FileManager.default.removeItem(at: url) }
        prune()
        return plan.summary
    }

    /// Startup housekeeping that never touches reusable downloads: interrupted
    /// work and pack archives an import already unpacked.
    public func removeLeftovers() {
        let scan = scan()
        for url in interrupted(scan) + scan.archives.filter({ $0.changed < now - recent }).map(\.url) { try? FileManager.default.removeItem(at: url) }
        prune()
    }

    /// A pack archive is read only while preparing an import; the prepared
    /// workspace holds its contents. Archives outside the cache belong to the user.
    public static func discardArchive(_ archive: URL, paths: LauncherPaths) {
        let root = paths.cache.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard archive.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root) else { return }
        try? FileManager.default.removeItem(at: archive)
    }

    struct Plan {
        var removals: [URL] = []
        var bytes: Int64 = 0
        var summary: Summary { .init(bytes: bytes, files: removals.count) }
    }

    func plan() -> Plan {
        let scan = scan()
        var plan = Plan()
        for url in interrupted(scan) { plan.removals.append(url); plan.bytes += footprint(url) }
        var groups: [UInt64: [Entry]] = [:]
        for entry in scan.files + scan.archives where entry.links == 1 {
            if let clone = entry.clone, entry.references != nil { groups[clone, default: []].append(entry); continue }
            // Without clone tracking, a file is unused when it shares no blocks.
            guard entry.changed < now - recent, entry.privateBytes >= entry.allocated else { continue }
            plan.removals.append(entry.url); plan.bytes += entry.privateBytes
        }
        for members in groups.values {
            let references = members.compactMap(\.references).max() ?? 0
            if references > members.count {
                // Game files still share these blocks. Keep one copy, preferring
                // the SHA-1 store that later downloads look up.
                let keep = members.first { $0.url.path.hasPrefix(cache.appendingPathComponent("objects").path + "/") } ?? members[0]
                plan.removals += members.filter { $0.url != keep.url && $0.changed < now - recent }.map(\.url)
            } else {
                guard members.allSatisfy({ $0.changed < now - recent }) else { continue }
                plan.removals += members.map(\.url)
                // Copies inside the cache share their blocks with each other.
                plan.bytes += members.count == 1 ? members[0].privateBytes : members.map(\.allocated).max() ?? 0
            }
        }
        return plan
    }

    struct Entry {
        let url: URL
        let allocated: Int64
        let changed: Date
        let links: UInt16
        let privateBytes: Int64
        let clone: UInt64?
        let references: UInt32?
    }
    struct Scan {
        var files: [Entry] = []
        var archives: [Entry] = []
        /// Partial downloads and copies a crash left behind.
        var temporary: [Entry] = []
        var workspaces: [URL] = []
    }

    func scan() -> Scan {
        var scan = Scan()
        let top = (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? []
        for url in top {
            let name = url.lastPathComponent
            if Self.workspacePrefixes.contains(where: name.hasPrefix) { scan.workspaces.append(url) }
            else if Self.workspaceFolders.contains(name) {
                scan.workspaces += (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            } else if name.hasPrefix("pack-"), name.hasSuffix(".mrpack"), let entry = Self.entry(url) { scan.archives.append(entry) }
        }
        scan.temporary += temporaryFiles(in: cache.appendingPathComponent(Self.partials))
        for store in Self.stores {
            let root = cache.appendingPathComponent(store)
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walk {
                let name = url.lastPathComponent
                if name == Self.partials { walk.skipDescendants(); scan.temporary += temporaryFiles(in: url); continue }
                guard let entry = Self.entry(url) else { continue }
                if name == ".DS_Store" { continue }
                if name.hasPrefix(".") { scan.temporary.append(entry) }
                else if store == "pack-updates" { scan.archives.append(entry) }
                else { scan.files.append(entry) }
            }
        }
        return scan
    }

    private func temporaryFiles(in directory: URL) -> [Entry] {
        // Lock files are shared with running downloads; prune removes idle ones.
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension != "lock" }.compactMap(Self.entry)
    }

    func interrupted(_ scan: Scan) -> [URL] {
        scan.workspaces.filter { (Self.changed($0) ?? now) < now - stale }
            + scan.temporary.filter { $0.changed < now - stale }.map(\.url)
    }

    /// Removes empty folders and the lock files no download holds.
    func prune() {
        var directories: [URL] = []
        for root in Self.stores.map(cache.appendingPathComponent) + Self.workspaceFolders.map(cache.appendingPathComponent) {
            guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            for case let url as URL in walk {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true { directories.append(url) }
            }
        }
        directories.append(cache.appendingPathComponent(Self.partials))
        for directory in directories.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            if directory.lastPathComponent == Self.partials {
                for lock in ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []) where lock.pathExtension == "lock" {
                    Self.removeIdleLock(lock)
                }
            }
            rmdir(directory.path)
        }
    }

    static func removeIdleLock(_ url: URL) {
        let fd = open(url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET); lock.l_len = 0
        // Unlink while holding the lock so no download is using this file.
        if fcntl(fd, F_OFD_SETLK, &lock) == 0 { unlink(url.path) }
    }

    func footprint(_ url: URL) -> Int64 {
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return Self.entry(url)?.privateBytes ?? 0 }
        var total = Self.entry(url)?.privateBytes ?? 0
        for case let file as URL in walk { total += Self.entry(file)?.privateBytes ?? 0 }
        return total
    }

    static func changed(_ url: URL) -> Date? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec) + TimeInterval(info.st_ctimespec.tv_nsec) / 1e9)
    }

    /// Regular files only. The status change time also moves when a file is
    /// renamed or cloned into place, unlike a modification time a copy keeps.
    static func entry(_ url: URL) -> Entry? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        let allocated = Int64(info.st_blocks) * 512
        let changed = Date(timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec) + TimeInterval(info.st_ctimespec.tv_nsec) / 1e9)
        let clones = cloneInfo(url.path)
        return Entry(url: url, allocated: allocated, changed: changed, links: info.st_nlink,
                     privateBytes: min(clones.privateBytes ?? allocated, allocated), clone: clones.id, references: clones.references)
    }

    /// APFS reports the bytes no other file shares, and which files are
    /// unmodified clones of each other. Other volumes have no clones.
    static func cloneInfo(_ path: String) -> (privateBytes: Int64?, id: UInt64?, references: UInt32?) {
        let size = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        // A system without clone counts rejects the request; the private size
        // alone still tells shared files apart.
        return attributes(path, size | attrgroup_t(ATTR_CMNEXT_CLONEID) | attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT))
            ?? attributes(path, size) ?? (nil, nil, nil)
    }

    private static func attributes(_ path: String, _ wanted: attrgroup_t) -> (privateBytes: Int64?, id: UInt64?, references: UInt32?)? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = wanted
        var buffer = [UInt8](repeating: 0, count: 64)
        guard getattrlist(path, &request, &buffer, buffer.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW)) == 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            // Layout: length, the returned attribute set, then each returned
            // attribute in bit order.
            let returned = raw.loadUnaligned(fromByteOffset: 4 + MemoryLayout<attrgroup_t>.size * 4, as: attrgroup_t.self)
            var offset = 4 + MemoryLayout<attribute_set_t>.size
            var result: (privateBytes: Int64?, id: UInt64?, references: UInt32?) = (nil, nil, nil)
            if returned & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 { result.privateBytes = raw.loadUnaligned(fromByteOffset: offset, as: Int64.self); offset += 8 }
            if returned & attrgroup_t(ATTR_CMNEXT_CLONEID) != 0 { result.id = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self); offset += 8 }
            if returned & attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT) != 0 { result.references = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
            // A clone count without its identity cannot group copies.
            if result.id == nil || result.references == 0 { result.id = nil; result.references = nil }
            return result
        }
    }
}
