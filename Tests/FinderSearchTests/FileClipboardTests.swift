import AppKit
import XCTest
@testable import FinderSearch

final class FileClipboardTests: XCTestCase {
    @MainActor func testCutFilesAndFoldersAcrossWindowsAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: file)
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("nested".utf8).write(to: folder.appendingPathComponent("nested.txt"))
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let clipboard = FileClipboard(pasteboard: .withUniqueName())
        defer { clipboard.pasteboard.releaseGlobally() }
        let source = SearchModel()
        source.hits = try [file, folder].map { try Hit.read($0) }
        source.selection = Set(source.hits.map(\.path))
        source.cut(clipboard: clipboard)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        let destination = SearchModel()
        destination.location = target; destination.route = target.path
        destination.paste(clipboard: clipboard)
        try await wait(destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(
            try String(
                contentsOf: target.appendingPathComponent("folder/nested.txt"), encoding: .utf8),
            "nested")
        XCTAssertTrue(clipboard.urls.isEmpty)
        XCTAssertTrue(clipboard.cutPaths.isEmpty)
        destination.undo()
        try await wait(destination)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "report")
        XCTAssertEqual(
            try String(contentsOf: folder.appendingPathComponent("nested.txt"), encoding: .utf8),
            "nested")
    }

    @MainActor func testFailedMovesRemainPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try Data("report".utf8).write(to: source)
        let missing = root.appendingPathComponent("missing.txt")
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let clipboard = FileClipboard(pasteboard: .withUniqueName())
        defer { clipboard.pasteboard.releaseGlobally() }
        clipboard.write([source, missing], cut: true)
        let model = SearchModel(); model.location = target; model.route = target.path
        model.paste(clipboard: clipboard)
        try await wait(model)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: target.appendingPathComponent("report.txt").path)
        )
        XCTAssertEqual(clipboard.urls, [missing])
        XCTAssertEqual(clipboard.cutPaths, [missing.path])
        XCTAssertTrue(clipboard.isCut)
        XCTAssertEqual(model.undoStack.count, 1)
    }

    @MainActor func testCopyAndExternalClipboardChangesCancelCutAndProtectNewContent() {
        let clipboard = FileClipboard(pasteboard: .withUniqueName())
        defer { clipboard.pasteboard.releaseGlobally() }
        let source = URL(fileURLWithPath: "/fixture/source")
        clipboard.write([source], cut: true)
        let oldCount = clipboard.pasteboard.changeCount
        clipboard.write([], cut: false)
        XCTAssertTrue(clipboard.isCut)
        clipboard.write([source], cut: false)
        XCTAssertFalse(clipboard.isCut)
        clipboard.write([source], cut: true)
        clipboard.finish(
            [.move(source, URL(fileURLWithPath: "/target/source"))], changeCount: oldCount)
        XCTAssertEqual(clipboard.urls, [source])
        clipboard.pasteboard.clearContents()
        clipboard.pasteboard.setString("new clipboard text", forType: .string)
        XCTAssertFalse(clipboard.isCut)
        clipboard.finish(
            [.move(source, URL(fileURLWithPath: "/target/source"))], changeCount: oldCount)
        XCTAssertEqual(clipboard.pasteboard.string(forType: .string), "new clipboard text")
    }

    @MainActor func testExternalCopyAutomaticallyClearsCutAppearance() async throws {
        let clipboard = FileClipboard(pasteboard: .withUniqueName())
        defer { clipboard.pasteboard.releaseGlobally() }
        let source = URL(fileURLWithPath: "/fixture/cut-file")
        clipboard.write([source], cut: true)
        XCTAssertEqual(clipboard.cutPaths, [source.path])
        clipboard.pasteboard.clearContents()
        clipboard.pasteboard.setString("copied elsewhere", forType: .string)
        for _ in 0..<100 {
            if clipboard.cutPaths.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(clipboard.cutPaths.isEmpty)
        XCTAssertEqual(clipboard.pasteboard.string(forType: .string), "copied elsewhere")
    }

    @MainActor private func wait(_ model: SearchModel) async throws {
        for _ in 0..<500 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("File operation did not finish")
    }
}
