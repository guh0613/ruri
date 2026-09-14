import Foundation
import RuriLocalization

/// Enforce the response limit while receiving, before an untrusted skin server
/// can allocate an unbounded response in memory.
enum AccountHTTPData {
    static func load(_ request: URLRequest, session: URLSession, delegate: any URLSessionTaskDelegate, limit: Int) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw RuriError.message(Messages.CoreAccountAppearance.invalidAppearanceResponse) }
        guard response.expectedContentLength <= limit else { throw RuriError.message(Messages.CoreAccountAppearance.appearanceDataTooLarge) }
        var data = Data(); data.reserveCapacity(min(max(Int(response.expectedContentLength), 0), limit))
        for try await byte in bytes {
            guard data.count < limit else { throw RuriError.message(Messages.CoreAccountAppearance.appearanceDataTooLarge) }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, response)
    }
}

/// Texture CDNs can use signed query strings. Their redirect policy is distinct
/// from authentication API discovery, and never forwards credentials or cookies.
final class PlayerTextureRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { completionHandler(nil); return }
        var safe = request; safe.httpShouldHandleCookies = false
        safe.setValue(nil, forHTTPHeaderField: "Authorization"); safe.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(safe)
    }
}
