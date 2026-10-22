import Foundation
import CoreFoundation

/// Read-only Finder view preferences. No Python runtime or Finder automation is needed.
struct FinderFolderSettings: Equatable, Sendable {
    struct Column: Equatable, Sendable {
        let identifier: String
        let width: Double?
        let visible: Bool?
        let index: Int
    }
    var columns: [Column] = []
    var view: FileViewMode?
    var sort: FileSort?
    var ascending: Bool?
    var iconSize: Double?
    var textSize: Double?

    static func read(folder: URL) -> Self? {
        let parent = folder.deletingLastPathComponent()
        var records =
            (try? DSStoreReader.read(
                parent.appendingPathComponent(".DS_Store"), filename: folder.lastPathComponent))
            ?? [:]
        // A local '.' record is used at volume roots and when Finder cannot write the parent.
        if let local = try? DSStoreReader.read(
            folder.appendingPathComponent(".DS_Store"), filename: ".")
        {
            records.merge(local) { _, local in local }
        }
        return decode(records)
    }

    static func decode(_ records: [String: Data]) -> Self? {
        guard !records.isEmpty else { return nil }
        func plist(_ code: String) -> [String: Any]? {
            guard let data = records[code] else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil))
                as? [String: Any]
        }
        func number(_ value: Any?, within range: ClosedRange<Double>) -> Double? {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                value.doubleValue.isFinite, range.contains(value.doubleValue)
            else { return nil }
            return value.doubleValue
        }
        var result = Self()
        if let data = records["vstl"], let code = String(data: data, encoding: .ascii) {
            result.view =
                [
                    "icnv": .icons, "Nlsv": .list, "clmv": .columns, "Flwv": .gallery,
                    "glyv": .gallery,
                ][code]
        }
        if let list = plist("lsvP") ?? plist("lsvp") {
            var source: [(String, [String: Any])] = []
            if let columns = list["columns"] as? [String: [String: Any]] {
                source = columns.map { ($0.key, $0.value) }
            } else if let columns = list["columns"] as? [[String: Any]] {
                source = columns.compactMap { column in
                    guard let name = column["identifier"] as? String else { return nil }
                    return (name, column)
                }
            }
            let identifiers = [
                "name": "name", "dateModified": "modified", "size": "size", "kind": "kind",
            ]
            result.columns = source.compactMap { name, values in
                guard let identifier = identifiers[name] else { return nil }
                return Column(
                    identifier: identifier, width: number(values["width"], within: 24...4096),
                    visible: values["visible"] as? Bool,
                    index: Int(number(values["index"], within: 0...100) ?? 100))
            }.sorted { ($0.index, $0.identifier) < ($1.index, $1.identifier) }
            var seen = Set<String>()
            result.columns = result.columns.filter { seen.insert($0.identifier).inserted }
            if let name = list["sortColumn"] as? String {
                result.sort =
                    ["name": .name, "dateModified": .modified, "size": .size, "kind": .kind][name]
                result.ascending = source.first { $0.0 == name }?.1["ascending"] as? Bool
            }
            result.textSize = number(list["textSize"], within: 9...32)
        }
        if let icons = plist("icvp") {
            result.iconSize = number(icons["iconSize"], within: 16...512)
        }
        return result == Self() ? nil : result
    }
}

/// Bounds-checked reader for the buddy allocator and B-tree in a .DS_Store file.
/// Format references: https://ds-store.readthedocs.io/ and Mac::Finder::DSStore.
/// Only active B-tree records are inspected; stale/free blocks are never scanned.
enum DSStoreReader {
    enum Invalid: Error { case file }
    private struct Cursor {
        let data: Data
        var offset = 0
        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0, offset <= data.count, count <= data.count - offset else {
                throw Invalid.file
            }
            defer { offset += count }
            return data.subdata(in: offset..<offset + count)
        }
        mutating func uint() throws -> Int {
            try bytes(4).reduce(0) { ($0 << 8) | Int($1) }
        }
        mutating func code() throws -> String {
            guard let string = String(data: try bytes(4), encoding: .ascii) else {
                throw Invalid.file
            }
            return string
        }
    }

    static func read(_ url: URL, filename: String) throws -> [String: Data] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // Limit memory/work even for damaged or unexpectedly large metadata files.
        guard let data = try handle.read(upToCount: 16 * 1024 * 1024 + 1),
            data.count <= 16 * 1024 * 1024
        else {
            throw Invalid.file
        }
        return try records(in: data, filename: filename)
    }

    static func records(in data: Data, filename: String) throws -> [String: Data] {
        var header = Cursor(data: data)
        guard try header.uint() == 1, try header.code() == "Bud1" else { throw Invalid.file }
        let rootOffset = try header.uint(), rootSize = try header.uint()
        guard try header.uint() == rootOffset else { throw Invalid.file }
        func slice(_ offset: Int, _ size: Int) throws -> Data {
            var cursor = Cursor(data: data, offset: offset)
            return try cursor.bytes(size)
        }
        var root = Cursor(data: try slice(rootOffset + 4, rootSize))
        let count = try root.uint()
        guard count > 0, count <= data.count / 4 else { throw Invalid.file }
        _ = try root.uint()
        var addresses: [Int] = []
        for _ in 0..<count { addresses.append(try root.uint()) }
        _ = try root.bytes((((count + 255) & ~255) - count) * 4)
        let tocCount = try root.uint()
        guard tocCount <= 256 else { throw Invalid.file }
        var database: Int?
        for _ in 0..<tocCount {
            let length = Int(try root.bytes(1).first!)
            let name = try root.bytes(length)
            let block = try root.uint()
            if name == Data("DSDB".utf8) { database = block }
        }
        func block(_ index: Int) throws -> Cursor {
            guard addresses.indices.contains(index) else { throw Invalid.file }
            let address = addresses[index]
            return Cursor(data: try slice((address & ~31) + 4, 1 << (address & 31)))
        }
        guard let database else { throw Invalid.file }
        var superblock = try block(database)
        let tree = try superblock.uint()
        var pending = [(tree, 0)], visited = Set<Int>(), result: [String: Data] = [:]
        let supported: Set<String> = ["lsvp", "lsvP", "icvp", "vstl"]
        while let (index, depth) = pending.popLast() {
            try Task.checkCancellation()
            guard depth < 64, visited.insert(index).inserted, visited.count <= 65536 else {
                throw Invalid.file
            }
            var node = try block(index)
            let next = try node.uint(), entries = try node.uint()
            guard entries <= node.data.count / 12 else { throw Invalid.file }
            if next != 0 { pending.append((next, depth + 1)) }
            for _ in 0..<entries {
                if next != 0 { pending.append((try node.uint(), depth + 1)) }
                let nameLength = try node.uint()
                let name = String(data: try node.bytes(nameLength * 2), encoding: .utf16BigEndian)
                let code = try node.code(), type = try node.code()
                let value: Data
                switch type {
                case "bool": value = try node.bytes(1)
                case "long", "shor", "type": value = try node.bytes(4)
                case "comp", "dutc": value = try node.bytes(8)
                case "blob":
                    let length = try node.uint()
                    value = try node.bytes(length)
                case "ustr":
                    let length = try node.uint()
                    value = try node.bytes(length * 2)
                default: throw Invalid.file
                }
                if name == filename, supported.contains(code),
                    (code == "vstl" ? type == "type" : type == "blob")
                {
                    result[code] = value
                }
            }
        }
        return result
    }
}
