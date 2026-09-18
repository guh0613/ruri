import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import RuriCore
import RuriLocalization

/// Accept Finder file URLs without moving the source or loading archive contents
/// while the pointer is hovering over the list.
struct ContentImportDropDelegate: DropDelegate {
    let isEnabled: Bool
    @Binding var itemCount: Int?
    let receive: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && info.hasItemsConforming(to: [.fileURL])
    }
    func dropEntered(info: DropInfo) {
        itemCount = validateDrop(info: info) ? info.itemProviders(for: [.fileURL]).count : nil
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .copy : .forbidden)
    }
    func dropExited(info: DropInfo) { itemCount = nil }
    func performDrop(info: DropInfo) -> Bool {
        itemCount = nil
        guard validateDrop(info: info) else { return false }
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        receive(providers)
        return true
    }

    static func fileURLs(from providers: [NSItemProvider]) async throws -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            try Task.checkCancellation()
            let url: URL = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadTransferable(type: URL.self) { result in continuation.resume(with: result) }
            }
            guard url.isFileURL else { throw RuriError.message(Messages.ContentImport.invalidDrop) }
            urls.append(url)
        }
        try Task.checkCancellation()
        return urls
    }
}
