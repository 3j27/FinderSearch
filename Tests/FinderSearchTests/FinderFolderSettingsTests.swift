import AppKit
import XCTest
@testable import FinderSearch

final class FinderFolderSettingsTests: XCTestCase {
    private func uint(_ value: Int) -> Data {
        var value = UInt32(value).bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    private func entry(_ filename: String, _ code: String, _ type: String, _ payload: Data) -> Data
    {
        var data = uint(filename.utf16.count)
        data += filename.data(using: .utf16BigEndian)!
        data += Data((code + type).utf8)
        if type == "blob" { data += uint(payload.count) }
        data += payload
        return data
    }
    private func plist(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
    // A buddy allocator, DSDB superblock and a leaf node, without a runtime dependency.
    private func store(_ records: [Data]) -> Data {
        var data = Data(repeating: 0, count: 12292)
        func put(_ offset: Int, _ bytes: Data) {
            data.replaceSubrange(offset..<offset + bytes.count, with: bytes)
        }
        put(0, uint(1) + Data("Bud1".utf8) + uint(2048) + uint(2048) + uint(2048))
        put(2052, uint(3) + uint(0) + uint(2048 | 11) + uint(4096 | 5) + uint(8192 | 12))
        put(3084, uint(1) + Data([4]) + Data("DSDB".utf8) + uint(1))
        put(4100, uint(2) + uint(0) + uint(records.count) + uint(1) + uint(4096))
        put(8196, uint(0) + uint(records.count) + records.reduce(Data(), +))
        return data
    }
    private func listProperties(width: Double = 581) -> [String: Any] {
        [
            "sortColumn": "dateModified", "textSize": 14,
            "columns": [
                "name": ["width": width, "visible": true, "index": 0, "ascending": true],
                "dateModified": ["width": 181, "visible": true, "index": 2, "ascending": false],
                "size": ["width": 97, "visible": false, "index": 1, "ascending": false],
                "comments": ["width": 300, "visible": true, "index": 3, "ascending": true],
            ],
        ]
    }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testReadsOnlyMatchingActiveRecordsAndMapsListSettings() throws {
        let data = try store([
            entry("other", "lsvp", "blob", plist(listProperties(width: 999))),
            entry("folder", "lsvp", "blob", plist(listProperties())),
            entry("folder", "vstl", "type", Data("Nlsv".utf8)),
            entry("folder", "icvp", "blob", plist(["iconSize": 128])),
        ])
        let records = try DSStoreReader.records(in: data, filename: "folder")
        let settings = try XCTUnwrap(FinderFolderSettings.decode(records))
        XCTAssertEqual(settings.view, .list)
        XCTAssertEqual(settings.sort, .modified)
        XCTAssertEqual(settings.ascending, false)
        XCTAssertEqual(settings.columns.map(\.identifier), ["name", "size", "modified"])
        XCTAssertEqual(settings.columns.first?.width, 581)
        XCTAssertEqual(settings.columns[1].visible, false)
        XCTAssertEqual(settings.textSize, 14)
        XCTAssertEqual(settings.iconSize, 128)
        XCTAssertTrue(try DSStoreReader.records(in: data, filename: "missing").isEmpty)
    }

    func testArrayColumnsAndInvalidNumbers() throws {
        let records = [
            "lsvP": try plist([
                "columns": [
                    ["identifier": "name", "width": -10, "index": 0],
                    ["identifier": "kind", "width": true, "index": 1],
                    ["identifier": "size", "width": 9000, "index": 2],
                    ["identifier": "name", "width": 400, "index": 3],
                ], "textSize": 1000,
            ]), "icvp": try plist(["iconSize": -1]),
        ]
        let settings = try XCTUnwrap(FinderFolderSettings.decode(records))
        XCTAssertEqual(settings.columns.count, 3)
        XCTAssertTrue(settings.columns.allSatisfy { $0.width == nil })
        XCTAssertNil(settings.textSize)
        XCTAssertNil(settings.iconSize)
        XCTAssertNil(FinderFolderSettings.decode(["lsvp": Data("bad plist".utf8)]))
    }

    func testParentRecordAndLocalOverrideAndMissingFiles() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertNil(FinderFolderSettings.read(folder: folder))
        try store([entry("folder", "lsvp", "blob", plist(listProperties()))])
            .write(to: root.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(FinderFolderSettings.read(folder: folder)?.columns.first?.width, 581)
        try store([entry(".", "lsvp", "blob", plist(listProperties(width: 420)))])
            .write(to: folder.appendingPathComponent(".DS_Store"))
        let before = try Data(contentsOf: folder.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(FinderFolderSettings.read(folder: folder)?.columns.first?.width, 420)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(".DS_Store")), before)
        try Data("invalid".utf8).write(to: folder.appendingPathComponent(".DS_Store"))
        XCTAssertEqual(FinderFolderSettings.read(folder: folder)?.columns.first?.width, 581)
    }

    func testTraversesInternalNodesAndIgnoresUnreferencedBytes() throws {
        var data = store([])
        data += Data(repeating: 0, count: 8192)
        func put(_ offset: Int, _ bytes: Data) {
            data.replaceSubrange(offset..<offset + bytes.count, with: bytes)
        }
        put(2052, uint(5))
        put(2072, uint(12288 | 12) + uint(16384 | 12))
        let list = try entry(".", "lsvp", "blob", plist(listProperties()))
        put(8196, uint(4) + uint(1) + uint(3) + list)
        put(12292, try uint(0) + uint(1) + entry(".", "icvp", "blob", plist(["iconSize": 96])))
        put(16388, uint(0) + uint(1) + entry(".", "vstl", "type", Data("Nlsv".utf8)))
        // A stale plist outside the active records must not override the real width.
        put(17000, try entry(".", "lsvp", "blob", plist(listProperties(width: 999))))
        let records = try DSStoreReader.records(in: data, filename: ".")
        let settings = try XCTUnwrap(FinderFolderSettings.decode(records))
        XCTAssertEqual(settings.columns.first?.width, 581)
        XCTAssertEqual(settings.iconSize, 96)
        XCTAssertEqual(settings.view, .list)
    }

    func testTruncatedCorruptAndCyclicFilesFailSafely() throws {
        let data = try store([entry(".", "lsvp", "blob", plist(listProperties()))])
        for length in [0, 4, 20, 2052, 3088, 4105, 8200] {
            XCTAssertThrowsError(
                try DSStoreReader.records(in: Data(data.prefix(length)), filename: "."))
        }
        var cyclic = data
        cyclic.replaceSubrange(8196..<8200, with: uint(2))
        cyclic.replaceSubrange(8200..<8204, with: uint(0))
        XCTAssertThrowsError(try DSStoreReader.records(in: cyclic, filename: "."))
        var badAddress = data
        badAddress.replaceSubrange(2068..<2072, with: uint(0xFFFFFFFC))
        XCTAssertThrowsError(try DSStoreReader.records(in: badAddress, filename: "."))
    }

    @MainActor func testAppliesToModelAndTableAndResetsOnNextFolder() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try store([
            entry(".", "lsvp", "blob", plist(listProperties())),
            entry(".", "vstl", "type", Data("Nlsv".utf8)),
            entry(".", "icvp", "blob", plist(["iconSize": 128])),
        ]).write(to: root.appendingPathComponent(".DS_Store"))
        let defaultView = UserDefaults.standard.string(forKey: "viewMode")
        let model = SearchModel()
        model.navigate(root)
        // The folder listing may finish before the view's settings task starts.
        for _ in 0..<200 where model.loading || model.sorting {
            try await Task.sleep(for: .milliseconds(5))
        }
        await model.loadFinderSettings()
        XCTAssertEqual(UserDefaults.standard.string(forKey: "viewMode"), defaultView)
        XCTAssertEqual(model.viewMode, .list)
        XCTAssertEqual(model.sort, .modified)
        XCTAssertFalse(model.ascending)
        XCTAssertEqual(model.iconSize, 128)
        let list = FileList(model: model, focusFiles: {}, newTab: { _ in })
        let coordinator = list.makeCoordinator()
        let scroll = list.makeView(coordinator: coordinator)
        coordinator.update()
        let table = try XCTUnwrap(scroll.documentView as? BrowserTable)
        XCTAssertEqual(
            table.tableColumns.map { $0.identifier.rawValue },
            ["name", "size", "modified", "kind", "where"])
        XCTAssertEqual(table.tableColumns[0].width, 581)
        XCTAssertTrue(table.tableColumns[1].isHidden)
        XCTAssertEqual(table.tableColumns[2].width, 181)
        // Metadata and selection updates must not undo a user's subsequent resizing.
        table.tableColumns[0].width = 650
        coordinator.update()
        XCTAssertEqual(table.tableColumns[0].width, 650)
        model.navigate(root)
        coordinator.update()
        XCTAssertNotNil(model.finderSettings)
        XCTAssertEqual(table.tableColumns[0].width, 650)
        model.navigate(other)
        await model.loadFinderSettings()
        coordinator.update()
        XCTAssertNil(model.finderSettings)
        XCTAssertEqual(model.iconSize, 64)
        XCTAssertEqual(table.tableColumns[0].width, 300)
        XCTAssertFalse(table.tableColumn(withIdentifier: .init("size"))!.isHidden)
    }
}
