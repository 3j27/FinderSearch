import Darwin
import Foundation
import XCTest
@testable import FinderSearch

final class RestrictedDaemonTests: XCTestCase {
    func testRestartPreservesIndexAndRefusesForeignExecutable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("index.bin")
        let contents = Data("saved index fixture".utf8)
        try contents.write(to: index)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [
            "-MIO::Handle", "-e",
            """
            open(my $lock, ">", "$ARGV[0]/socket.lock") or die $!;
            flock($lock, 2) or die $!;
            print $lock "$$";
            $lock->flush();
            open(my $ready, ">", "$ARGV[0]/ready") or die $!;
            close($ready);
            sleep 30;
            """, directory.path,
        ]
        try child.run()
        defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("ready").path),
            ProcessInfo.processInfo.systemUptime < deadline
        { Thread.sleep(forTimeInterval: 0.01) }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path)
        else { XCTFail("Daemon fixture did not start"); return }
        XCTAssertFalse(
            try RestrictedDaemon.recover(
                binary: "/not/this/installation/fsearch", directory: directory))
        XCTAssertTrue(child.isRunning)
        var executable = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        XCTAssertGreaterThan(
            proc_pidpath(child.processIdentifier, &executable, UInt32(executable.count)), 0)
        XCTAssertTrue(
            try RestrictedDaemon.recover(binary: String(cString: executable), directory: directory))
        child.waitUntilExit()
        XCTAssertEqual(try Data(contentsOf: index), contents)
    }

    func testMissingDaemonDoesNotRequireRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        XCTAssertFalse(try RestrictedDaemon.recover(binary: "/missing", directory: directory))
    }
}
