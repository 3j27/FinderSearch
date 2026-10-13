import AppKit
import Combine
import SwiftUI
import XCTest
@testable import FinderSearch

final class SelectionNavigationTests: XCTestCase {
    @MainActor private func loaded(_ model: SearchModel) async throws {
        for _ in 0..<500 {
            if !model.loading && !model.sorting && !model.sortedHits.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Fixture did not load")
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "c.txt", "d.txt"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        return root
    }

    @MainActor func testMouseSelectionDoesNotRequestScrollingButKeyboardDoes() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SearchModel()
        model.navigate(root)
        try await loaded(model)
        var requests: [String] = []
        let token = model.selectionNavigation.sink { requests.append($0.path) }
        defer { token.cancel() }
        let items = model.sortedHits
        model.select(items[0], extending: false, toggling: false)
        model.select(items[2], extending: true, toggling: false)
        XCTAssertEqual(model.selection, Set(items.prefix(3).map(\.path)))
        XCTAssertTrue(requests.isEmpty, "Mouse selection must keep the viewport still")
        model.moveSelection(by: 1, extending: true)
        XCTAssertEqual(model.selection, Set(items.map(\.path)))
        XCTAssertEqual(requests, [items[3].path])
        model.moveSelection(by: -2, extending: true)
        XCTAssertEqual(model.selection, Set(items.prefix(2).map(\.path)))
        XCTAssertEqual(requests.last, items[1].path)
        model.beginRename(items[0])
        XCTAssertEqual(requests.last, items[0].path, "An offscreen rename target must be revealed")
        XCTAssertEqual(model.renaming?.path, items[0].path)
    }

    @MainActor func testColumnFocusDoesNotCollapseKeyboardOrMouseRanges() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SearchModel()
        model.navigate(root)
        try await loaded(model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            ColumnBrowser(model: model, focusFiles: {}, rowMenu: { _ in EmptyView() }))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(100))
        let items = model.sortedHits
        model.select(items[0], extending: false, toggling: false)
        try await Task.sleep(for: .milliseconds(50))
        model.moveSelection(by: 2, extending: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selection, Set(items.prefix(3).map(\.path)))
        model.moveSelection(by: -1, extending: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selection, Set(items.prefix(2).map(\.path)))
        model.select(items[3], extending: true, toggling: false, in: items)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selection, Set(items.map(\.path)))
        XCTAssertEqual(model.location, root.standardizedFileURL)
    }

    @MainActor func testReturningToParentColumnPreservesRangeAnchor() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let model = SearchModel()
        model.navigate(root)
        try await loaded(model)
        let items = model.sortedHits
        let anchor = try XCTUnwrap(items.first { $0.name == "c.txt" })
        let end = try XCTUnwrap(items.first { $0.name == "a.txt" })
        model.navigate(child)
        model.select(anchor, extending: false, toggling: false, in: items)
        model.navigate(root, preservingSelection: true)
        model.select(end, extending: true, toggling: false, in: items)
        XCTAssertEqual(Set(model.selection.map { URL(fileURLWithPath: $0).lastPathComponent }),
            ["a.txt", "b.txt", "c.txt"])
    }
}
