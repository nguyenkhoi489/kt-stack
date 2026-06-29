import GRDB
import XCTest
@testable import KTStackKit

/// SQLite round-trip runs without any managed engine so it's allowed under `xcodebuild test`.
/// F4 regression: ensure stale `-wal`/`-shm` sidecars don't survive an overwrite restore — SQLite
/// replaying a journal against the new file would corrupt it.
final class SQLiteBackupRoundTripTests: XCTestCase {
    private var workDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ktstack-sqlite-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workDir)
        try await super.tearDown()
    }

    func testBackupAndRestoreOverwriteRoundTrip() async throws {
        let dbPath = workDir.appendingPathComponent("source.sqlite").path
        try seedDatabase(at: dbPath, rows: [1, 2, 3])

        let profile = ConnectionProfile(
            name: "test",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: "main",
            filePath: dbPath,
            readOnly: false
        )
        let provider = SQLiteBackupProvider()
        let snapshot = workDir.appendingPathComponent("snapshot.sqlite")
        try await provider.backup(profile: profile, password: nil, database: "main", to: snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))

        try corruptDatabase(at: dbPath)

        try await provider.restore(profile: profile, password: nil, from: snapshot, into: .overwrite)

        let restoredRows = try fetchRows(at: dbPath)
        XCTAssertEqual(restoredRows, [1, 2, 3])

        for suffix in ["-wal", "-shm", "-journal"] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: dbPath + suffix),
                "Stale SQLite sidecar \(suffix) survived the restore"
            )
        }
    }

    func testRestoreNewDatabaseDoesNotOverwriteExistingFile() async throws {
        let dbPath = workDir.appendingPathComponent("source.sqlite").path
        try seedDatabase(at: dbPath, rows: [10])
        let target = workDir.appendingPathComponent("existing.sqlite")
        try Data("hi".utf8).write(to: target)

        let provider = SQLiteBackupProvider()
        let profile = ConnectionProfile(
            name: "test",
            kind: .sqlite,
            host: "",
            port: 0,
            user: "",
            database: "main",
            filePath: dbPath,
            readOnly: false
        )
        let snapshot = workDir.appendingPathComponent("snap.sqlite")
        try await provider.backup(profile: profile, password: nil, database: "main", to: snapshot)

        do {
            try await provider.restore(
                profile: profile,
                password: nil,
                from: snapshot,
                into: .newDatabase(target.path)
            )
            XCTFail("expected failure when the new database path already exists")
        } catch {}
        XCTAssertEqual(try String(contentsOf: target), "hi")
    }

    private func seedDatabase(at path: String, rows: [Int]) throws {
        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE numbers (n INTEGER PRIMARY KEY)")
            for value in rows {
                try db.execute(sql: "INSERT INTO numbers VALUES (?)", arguments: [value])
            }
        }
    }

    /// Append junk to the live DB file so a successful restore is observable (junk gone, rows back).
    private func corruptDatabase(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 0xFF, count: 4096))
        try handle.close()
    }

    private func fetchRows(at path: String) throws -> [Int] {
        let queue = try DatabaseQueue(path: path)
        return try queue.read { db in
            try Int.fetchAll(db, sql: "SELECT n FROM numbers ORDER BY n")
        }
    }
}
