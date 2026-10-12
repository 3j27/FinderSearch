import SwiftUI
import UniformTypeIdentifiers

/// Accept file URLs as shortcuts; never copy or move the dropped folders.
@MainActor enum FavoriteFolderDrop {
    static func perform(
        _ providers: [NSItemProvider], add: @escaping ([URL]) async -> Bool
    ) -> Bool {
        let providers = providers.filter { $0.canLoadObject(ofClass: NSURL.self) }
        guard !providers.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadObject(ofClass: NSURL.self) { object, _ in
                        continuation.resume(returning: (object as? NSURL).map { $0 as URL })
                    }
                }
                if let url { urls.append(url) }
            }
            _ = await add(urls)
        }
        return true
    }
}
