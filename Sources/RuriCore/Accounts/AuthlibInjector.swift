import RuriLocalization
import Foundation
import CryptoKit

public struct ExternalAuthLaunch: Sendable {
    public let jar: URL
    public let metadata: ExternalAuthMetadata
    public let userProperties: String
    public init(jar: URL, metadata: ExternalAuthMetadata, userProperties: String = "{}") {
        self.jar = jar; self.metadata = metadata; self.userProperties = userProperties
    }
    func arguments(for account: Account) throws -> [String] {
        guard account.kind == .external, account.externalLogin?.server.url == metadata.server.url,
              FileManager.default.fileExists(atPath: jar.path) else { throw RuriError.message(Messages.CoreAuthlibInjector.externalAuthComponentNotReady) }
        return ["-javaagent:\(jar.path)=\(metadata.server.url.absoluteString)",
                "-Dauthlibinjector.yggdrasil.prefetched=" + metadata.data.base64EncodedString()]
    }
}

public struct AuthlibInjector: Sendable {
    private struct Artifact: Codable, Sendable {
        struct Checksums: Codable, Sendable { let sha256: String }
        let build_number: Int
        let version: String
        let download_url: URL
        let checksums: Checksums
        func validate() throws {
            guard build_number > 0, download_url.scheme == "https", download_url.user == nil, download_url.password == nil,
                  checksums.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                throw RuriError.message(Messages.CoreAuthlibInjector.invalidAuthlibInjectorDownloadInfo)
            }
        }
        func file(in directory: URL) -> URL { directory.appendingPathComponent(checksums.sha256.lowercased() + ".jar") }
        func matches(_ data: Data) -> Bool { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == checksums.sha256.lowercased() }
    }
    private let http: HTTPClient
    public init(http: HTTPClient = .shared) { self.http = http }

    public func prepare(paths: LauncherPaths) async throws -> URL {
        let directory = paths.cache.appendingPathComponent("authlib-injector")
        let record = directory.appendingPathComponent("artifact.json")
        let cached = (try? Data(contentsOf: record)).flatMap { try? JSONDecoder().decode(Artifact.self, from: $0) }
        func cachedFile() -> URL? {
            guard let cached, (try? cached.validate()) != nil,
                  let data = try? Data(contentsOf: cached.file(in: directory)), cached.matches(data) else { return nil }
            return cached.file(in: directory)
        }
        let saved = (try? record.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let saved, Date().timeIntervalSince(saved) < 86_400, let file = cachedFile() { return file }
        let artifact: Artifact
        do {
            artifact = try await http.get(Artifact.self, from: URL(string: "https://authlib-injector.yushi.moe/artifact/latest.json")!)
            try artifact.validate()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if let file = cachedFile() { return file }
            throw error
        }
        let target = artifact.file(in: directory)
        if let data = try? Data(contentsOf: target), artifact.matches(data) {
            try JSONEncoder().encode(artifact).write(to: record, options: .atomic)
            return target
        }
        let data = try await http.data(from: artifact.download_url)
        guard data.count <= 8_388_608, artifact.matches(data) else { throw RuriError.message(Messages.CoreAuthlibInjector.authlibInjectorChecksumFailed) }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        try JSONEncoder().encode(artifact).write(to: record, options: .atomic)
        return target
    }
}
