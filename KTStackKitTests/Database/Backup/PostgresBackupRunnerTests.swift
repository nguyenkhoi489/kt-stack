import XCTest
@testable import KTStackKit

final class PostgresBackupRunnerTests: XCTestCase {
    private var runner: PostgresBackupRunner!

    override func setUp() {
        super.setUp()
        runner = PostgresBackupRunner()
    }

    /// F9: PGPASSFILE is created mode 0600 (not chmod-after), so the password is never briefly
    /// world-readable. The pgpass format is `host:port:db:user:password`.
    func testPasswordFileIsCreatedMode0600() throws {
        let url = try XCTUnwrap(try runner.writePasswordFile("s3cr3t"))
        defer { try? FileManager.default.removeItem(at: url) }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let content = try String(contentsOf: url)
        XCTAssertTrue(content.contains(":s3cr3t"))
    }

    /// F9: the pgpass file is `:`-delimited so a colon in the password can't be carried; reject loud.
    func testPasswordRejectsColon() {
        XCTAssertThrowsError(try runner.writePasswordFile("bad:pass"))
    }

    func testPasswordRejectsNewline() {
        XCTAssertThrowsError(try runner.writePasswordFile("bad\npass"))
    }

    func testNilOrEmptyPasswordWritesNoFile() throws {
        XCTAssertNil(try runner.writePasswordFile(nil))
        XCTAssertNil(try runner.writePasswordFile(""))
    }

    func testConnectionArgsRejectsBadHost() {
        var profile = ConnectionProfile.managedPostgres
        profile.host = "-h"
        XCTAssertThrowsError(try runner.connectionArgs(profile))
    }
}
