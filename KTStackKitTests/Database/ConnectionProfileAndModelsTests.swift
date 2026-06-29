import XCTest
@testable import KTStackKit

final class ConnectionProfileAndModelsTests: XCTestCase {
    func testCellDisplayTextDistinguishesNullFromEmptyText() {
        XCTAssertNil(Cell.null.displayText) // NULL → no text (view styles a placeholder)
        XCTAssertEqual(Cell.text("").displayText, "") // empty string stays distinct from NULL
        XCTAssertEqual(Cell.text("NULL").displayText, "NULL")
    }

    func testCellDisplayTextForScalars() {
        XCTAssertEqual(Cell.int(42).displayText, "42")
        XCTAssertEqual(Cell.bool(true).displayText, "1")
        XCTAssertEqual(Cell.bool(false).displayText, "0")
        XCTAssertEqual(Cell.blob(Data([0, 1, 2])).displayText, "[3 bytes]")
    }

    func testQueryResultReportsColumnsIndependentlyOfRows() {
        let result = QueryResult(columns: [ColumnMeta(name: "a"), ColumnMeta(name: "b")], rows: [])
        XCTAssertEqual(result.columnNames, ["a", "b"]) // headers survive a zero-row result
        XCTAssertEqual(result.rowCount, 0)
    }

    func testProfileCodableRoundTripPreservesFields() throws {
        let profile = ConnectionProfile(
            name: "prod-read", kind: .postgres, host: "db.example.com",
            port: 5432, user: "reader", database: "app", tlsMode: .verifyFull
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func testEncodedProfileJSONNeverContainsAPasswordField() throws {
        let profile = ConnectionProfile(
            name: "x", kind: .mysql, host: "h", port: 3306, user: "u", database: "d"
        )
        let json = try String(decoding: JSONEncoder().encode(profile), as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains("password")) // secrets live only in the Keychain, keyed by id
        XCTAssertFalse(json.contains("secret"))
    }

    func testTLSDefaultsToVerifyFullForRemoteAndPreferForLoopback() {
        let remote = ConnectionProfile(
            name: "r",
            kind: .mysql,
            host: "10.0.0.5",
            port: 3306,
            user: "u",
            database: "d"
        )
        XCTAssertEqual(remote.tlsMode, .verifyFull) // fails closed for non-loopback

        let local = ConnectionProfile(
            name: "l",
            kind: .mysql,
            host: "127.0.0.1",
            port: 3306,
            user: "u",
            database: "d"
        )
        XCTAssertEqual(local.tlsMode, .prefer)
    }

    func testReadOnlyDefaultsOnForRemoteOffForLoopbackAndManaged() {
        let remote = ConnectionProfile(
            name: "r",
            kind: .mysql,
            host: "10.0.0.5",
            port: 3306,
            user: "u",
            database: "d"
        )
        XCTAssertTrue(remote.readOnly) // external default ON — the server rejects stray writes
        let local = ConnectionProfile(
            name: "l",
            kind: .mysql,
            host: "127.0.0.1",
            port: 3306,
            user: "u",
            database: "d"
        )
        XCTAssertFalse(local.readOnly)
        XCTAssertFalse(ConnectionProfile.managedMySQL.readOnly)
    }

    func testDecodingLegacyProfileWithoutReadOnlyUsesHostDefault() throws {
        // A profile saved before the field existed: an absent `readOnly` must not fail the decode
        // (which would back up + drop the user's saved connections) — it falls back to the host default.
        let legacy = #"""
        {"id":"11111111-1111-1111-1111-111111111111","name":"p","kind":"mysql",\#
        "host":"10.0.0.5","port":3306,"user":"u","database":"d","tlsMode":"verifyFull"}
        """#
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.readOnly) // non-loopback host → defaults ON
    }

    func testManagedProfileIsLoopbackRootAndFlaggedManaged() {
        let managed = ConnectionProfile.managedMySQL
        XCTAssertTrue(managed.isManaged)
        XCTAssertEqual(managed.host, "127.0.0.1")
        XCTAssertEqual(managed.user, "root")
        // A user-created profile with the same coordinates is NOT the managed one (id differs).
        let lookalike = ConnectionProfile(
            name: "x",
            kind: .mysql,
            host: "127.0.0.1",
            port: 3306,
            user: "root",
            database: "mysql"
        )
        XCTAssertFalse(lookalike.isManaged)
    }
}
