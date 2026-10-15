import SwiftUI
import XCTest
@testable import FinderSearch

final class GoDestinationTests: XCTestCase {
    func testFinderShortcutsAreDistinctIncludingDownloadsAndLibrary() {
        let shortcuts = GoDestination.allCases.map { "\($0.modifiers.rawValue):\($0.key)" }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
        XCTAssertEqual(GoDestination.documents.key, "o")
        XCTAssertEqual(GoDestination.documents.modifiers, [.command, .shift])
        XCTAssertEqual(GoDestination.downloads.key, "l")
        XCTAssertEqual(GoDestination.downloads.modifiers, [.command, .option])
        XCTAssertEqual(GoDestination.library.modifiers, [.command, .shift])
        XCTAssertEqual(GoDestination.recents.key, "f")
    }
    func testDestinationsUseExistingSidebarRoutes() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(GoDestination.recents.route, "recents")
        XCTAssertEqual(GoDestination.home.route, home)
        XCTAssertEqual(GoDestination.documents.route, home + "/Documents")
        XCTAssertEqual(GoDestination.desktop.route, home + "/Desktop")
        XCTAssertEqual(GoDestination.downloads.route, home + "/Downloads")
        XCTAssertEqual(GoDestination.library.route, home + "/Library")
        XCTAssertEqual(GoDestination.applications.route, "/Applications")
        XCTAssertEqual(GoDestination.utilities.route, "/Applications/Utilities")
    }
}
