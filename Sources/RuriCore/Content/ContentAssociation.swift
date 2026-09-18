import Foundation
import RuriLocalization

extension ContentManager {
    /// Record exact online identities when the user checks for updates. Merely
    /// viewing details never changes tracking or the original acquisition source.
    public func associate(_ files: [LocalContentFile], matches: [String: [ContentIdentity]]) throws -> [String] {
        try lock(); defer { unlock() }
        try recover(); try Task.checkCancellation()
        let original = try readRecords()
        var records = original, skipped: [String] = []
        let proposals = files.compactMap { file -> (LocalContentFile, ContentIdentity)? in
            guard file.managed == nil || file.managed?.provider == "local",
                  let match = matches[file.id]?.first(where: { $0.record.kind == file.kind }) else { return nil }
            return (file, match)
        }
        let counts = Dictionary(proposals.map { ($0.1.record.id, 1) }, uniquingKeysWith: +)
        for (file, identity) in proposals {
            var record = identity.record
            if counts[record.id] != 1 || records.contains(where: { $0.id == record.id }) { skipped.append(file.filename); continue }
            let path = file.kind.folder + "/" + file.filename + (file.enabled ? "" : ".disabled")
            let expected = try contentURL(path)
            guard expected.standardizedFileURL == file.url.standardizedFileURL,
                  original.first(where: { $0.relativePath == path }) == file.managed else { throw RuriError.message(Messages.ContentDetails.fileChanged(file.filename)) }
            let digest = try ContentFileDigest.read(expected)
            guard digest.sha512 == record.sha512, digest.size == record.size else { throw RuriError.message(Messages.ContentDetails.fileChanged(file.filename)) }
            record.filename = file.filename; record.enabled = file.enabled
            record.installationSource = file.managed?.installationSource ?? file.managed?.provider ?? "local"
            records.removeAll { $0.relativePath == path }; records.append(record)
        }
        try Task.checkCancellation()
        if records != original { try writeRecords(records) }
        return skipped
    }
}
