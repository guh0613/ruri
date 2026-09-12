import RuriLocalization
import Foundation

/// Accept raw path components, not pre-escaped paths. A slash inside a value is
/// encoded as data; query values are encoded separately by Foundation.
enum EndpointURL {
    static func build(base: URL, path: [String] = [], query: [URLQueryItem] = []) throws -> URL {
        var result = base
        for component in path {
            guard !component.isEmpty, component != ".", component != "..",
                  !component.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw RuriError.message(Messages.CoreEndpointURL.resultText1)
            }
            result = result.appending(component: component, directoryHint: .notDirectory)
        }
        guard !query.isEmpty else { return result }
        guard var parts = URLComponents(url: result, resolvingAgainstBaseURL: false) else { throw RuriError.message(Messages.CoreEndpointURL.partsText1) }
        parts.queryItems = (parts.queryItems ?? []) + query
        // Form-style query decoders treat a literal + as a space. Preserve the
        // caller's plus signs without double-encoding existing percent escapes.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw RuriError.message(Messages.CoreEndpointURL.urlText1) }
        return url
    }

    static func belongsTo(_ url: URL, origin: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == origin.host?.lowercased() &&
        (url.port ?? 443) == (origin.port ?? 443) && url.user == nil && url.password == nil
    }
}
