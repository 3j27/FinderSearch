import AppKit
import Combine

/// Cut is deferred until Paste succeeds. Change counts prevent an older move
/// from consuming a newer clipboard, including a copy made in another app.
@MainActor final class FileClipboard: ObservableObject {
    static let shared = FileClipboard(pasteboard: .general)
    let pasteboard: NSPasteboard
    private var cutChangeCount: Int?
    @Published private(set) var cutPaths: Set<String> = []
    private var clipboardTimer: Timer?

    func opacity(for path: String) -> Double { cutPaths.contains(path) ? 0.45 : 1 }

    func refresh() {
        guard !isCut else { return }
        cutChangeCount = nil
        updateCutPaths([])
    }

    private func updateCutPaths(_ paths: Set<String>) {
        if cutPaths != paths { cutPaths = paths }
        if paths.isEmpty {
            clipboardTimer?.invalidate(); clipboardTimer = nil
        } else if clipboardTimer == nil {
            // NSPasteboard has no change notification. Poll only while a cut
            // is pending, including while menus or drag tracking are active.
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            clipboardTimer = timer
        }
    }

    deinit { clipboardTimer?.invalidate() }

    init(pasteboard: NSPasteboard) { self.pasteboard = pasteboard }

    func write(_ urls: [URL], cut: Bool) {
        guard !urls.isEmpty else { return }
        pasteboard.clearContents()
        let written = pasteboard.writeObjects(urls.map { $0 as NSURL })
        cutChangeCount = cut && written ? pasteboard.changeCount : nil
        updateCutPaths(cut && written ? Set(urls.map(\.path)) : [])
    }

    var urls: [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
    }
    var isCut: Bool { cutChangeCount == pasteboard.changeCount }

    func finish(_ operations: [FileMutation], changeCount: Int) {
        guard isCut, pasteboard.changeCount == changeCount else { return }
        let moved = Set(
            operations.compactMap { operation -> URL? in
                switch operation {
                case .move(let source, _): return source
                case .replace(let source, _, let move): return move ? source : nil
                default: return nil
                }
            })
        guard !moved.isEmpty else { return }
        let remaining = urls.filter { !moved.contains($0) }
        if remaining.isEmpty {
            pasteboard.clearContents()
            cutChangeCount = nil
            updateCutPaths([])
        } else {
            write(remaining, cut: true)
        }
    }
}
