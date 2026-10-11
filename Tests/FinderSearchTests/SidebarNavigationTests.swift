import AppKit
import XCTest
@testable import FinderSearch

final class SidebarNavigationTests: XCTestCase {
    @MainActor func testFavoritesMigrationOrderingRemovalAndWindowSynchronization() throws {
        let suite = "FinderSearch.sidebar.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let custom = "/fixture/custom"
        defaults.set([custom, custom, "/Applications"], forKey: "favorites")
        func workspace() -> BrowserWorkspace {
            BrowserWorkspace(volumeLoader: { [] }, favoritesDefaults: defaults)
        }
        let first = workspace(), second = workspace()
        XCTAssertEqual(first.favorites, FavoriteFolders.defaults() + [custom])
        let initial = first.favorites
        first.moveFavorites(from: IndexSet(integer: initial.count - 1), to: 0)
        XCTAssertEqual(first.favorites, [custom] + FavoriteFolders.defaults())
        XCTAssertEqual(second.favorites, first.favorites)
        first.removeFavorite("/Applications")
        XCTAssertFalse(first.favorites.contains("/Applications"))
        XCTAssertEqual(workspace().favorites, first.favorites)
        XCTAssertEqual(
            defaults.stringArray(forKey: "favorites"), [custom, custom, "/Applications"])
        // Re-add uses the same persistent list and refuses duplicates.
        first.addFavorite(URL(fileURLWithPath: "/Applications"))
        first.addFavorite(URL(fileURLWithPath: "/Applications"))
        XCTAssertEqual(first.favorites.filter { $0 == "/Applications" }.count, 1)
        XCTAssertEqual(first.favorites.last, "/Applications")
        for path in first.favorites { first.removeFavorite(path) }
        XCTAssertTrue(workspace().favorites.isEmpty)
    }

    @MainActor func testRemovedShortcutDoesNotRemainSelectedAndInvalidReorderIsIgnored() throws {
        let suite = "FinderSearch.sidebar.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = BrowserWorkspace(volumeLoader: { [] }, favoritesDefaults: defaults)
        let initial = workspace.favorites
        workspace.moveFavorites(from: IndexSet(integer: 999), to: 0)
        workspace.moveFavorites(from: IndexSet(integer: 0), to: -1)
        XCTAssertEqual(workspace.favorites, initial)
        workspace.removeFavorite("/Applications")
        let state = SidebarState(
            route: "/Applications", favorites: workspace.favorites,
            volumes: [], ejectingVolumes: [], showDiskAccessHint: false)
        XCTAssertNil(state.selection)
    }

    func testMouseButtonMappingLeavesMiddleClickAndUnrelatedEventsAlone() {
        XCTAssertEqual(MouseNavigationCommand.command(type: .otherMouseDown, button: 3), .back)
        XCTAssertEqual(MouseNavigationCommand.command(type: .otherMouseDown, button: 4), .forward)
        for button in [0, 1, 2, 5] {
            XCTAssertNil(MouseNavigationCommand.command(type: .otherMouseDown, button: button))
        }
        XCTAssertNil(MouseNavigationCommand.command(type: .otherMouseUp, button: 3))
        XCTAssertNil(MouseNavigationCommand.command(type: .keyDown, button: 3))
    }

    @MainActor func testMouseNavigationTargetsItsWindowAndUpdatedTab() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var first: [MouseNavigationCommand] = [], second: [MouseNavigationCommand] = []
        let view = MouseNavigationView {
            first.append($0); return true
        }
        window.contentView = view
        XCTAssertFalse(view.handle(.back, in: other))
        XCTAssertFalse(view.handle(.back, in: nil))
        XCTAssertFalse(view.handle(nil, in: window))
        XCTAssertTrue(view.handle(.back, in: window))
        XCTAssertEqual(first, [.back])
        view.navigate = {
            second.append($0); return true
        }
        XCTAssertTrue(view.handle(.forward, in: window))
        XCTAssertEqual(first, [.back])
        XCTAssertEqual(second, [.forward])
        view.navigate = { _ in false }
        XCTAssertFalse(view.handle(.back, in: window))
        window.contentView = nil
        XCTAssertFalse(view.handle(.back, in: window))
    }
    @MainActor func testFavoriteDragOnlyReordersAfterDraggingOntoAnotherRow() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let source = FavoriteDragView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let target = FavoriteDragView(frame: NSRect(x: 0, y: 50, width: 200, height: 30))
        source.path = "/source"; target.path = "/target"
        container.addSubview(source); container.addSubview(target); window.contentView = container
        var moves: [(String, String)] = []
        source.move = { moves.append(($0, $1)) }
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 0))
        }
        let start = CGPoint(x: 20, y: 15), end = CGPoint(x: 20, y: 65)
        XCTAssertFalse(source.handle(try event(.leftMouseDown, start)))
        XCTAssertFalse(source.handle(try event(.leftMouseUp, start)))
        XCTAssertTrue(moves.isEmpty)
        XCTAssertFalse(source.handle(try event(.leftMouseDown, start)))
        XCTAssertTrue(source.handle(try event(.leftMouseDragged, end)))
        XCTAssertTrue(moves.isEmpty)
        let preview = try XCTUnwrap(source.dragPreview)
        let marker = try XCTUnwrap(source.insertionMarker)
        XCTAssertTrue(preview.superview === container)
        XCTAssertFalse(marker.isHidden)
        let previousOrigin = preview.frame.origin
        XCTAssertTrue(source.handle(try event(.leftMouseDragged, CGPoint(x: 30, y: 66))))
        XCTAssertNotEqual(preview.frame.origin, previousOrigin)
        XCTAssertTrue(source.handle(try event(.leftMouseUp, end)))
        XCTAssertNil(source.dragPreview)
        XCTAssertNil(source.insertionMarker)
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.0, "/source")
        XCTAssertEqual(moves.first?.1, "/target")
        XCTAssertFalse(source.handle(try event(.leftMouseUp, end)))
        XCTAssertFalse(source.handle(try event(.leftMouseDown, start)))
        XCTAssertTrue(source.handle(try event(.leftMouseDragged, end)))
        let escape = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                keyCode: 53))
        XCTAssertTrue(source.handle(escape))
        XCTAssertNil(source.dragPreview)
        XCTAssertNil(source.insertionMarker)
        XCTAssertFalse(source.handle(try event(.leftMouseUp, end)))
        XCTAssertEqual(moves.count, 1)
        window.contentView = nil
    }

}
