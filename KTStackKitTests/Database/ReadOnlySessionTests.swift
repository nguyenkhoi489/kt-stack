import XCTest
@testable import KTStackKit

/// Opt-in proof that read-only is enforced by the SERVER, not the client: a profile flagged read-only
/// opens a session whose subsequent transactions are READ ONLY, so the server rejects an INSERT. Gated
/// on `KTSTACK_DB_IT=1` + an installed, running managed MySQL on :3306, so a clean CI box skips rather
/// than fails. Sets up a scratch database with a writable driver and tears it down at the end.
final class ReadOnlySessionTests: XCTestCase {
    private let scratchDB = "ktstack_ro_probe"

    private func skipUnlessEngine() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KTSTACK_DB_IT"] == "1",
            "Set KTSTACK_DB_IT=1 with the MySQL engine installed + running on :3306."
        )
        try XCTSkipUnless(
            ServiceBinaryCatalog(paths: AppSupportPaths()).isInstalled(.mysql),
            "MySQL engine not installed."
        )
    }

    /// A loopback root profile (the managed engine is passwordless). `readOnly` is parameterized so the
    /// same coordinates yield a writable setup driver and a read-only probe driver.
    private func loopbackProfile(readOnly: Bool) -> ConnectionProfile {
        ConnectionProfile(
            name: "ro-test",
            kind: .mysql,
            host: "127.0.0.1",
            port: 3306,
            user: "root",
            database: "mysql",
            tlsMode: .prefer,
            readOnly: readOnly
        )
    }

    func testReadOnlySessionRejectsInsertAtServer() async throws {
        try skipUnlessEngine()
        let writable = MySQLDriver(profile: loopbackProfile(readOnly: false), password: nil)
        _ = try await writable.query("CREATE DATABASE IF NOT EXISTS \(scratchDB)", database: nil)
        _ = try await writable.query(
            "CREATE TABLE IF NOT EXISTS \(scratchDB).t (id INT PRIMARY KEY)", database: nil
        )

        let readonly = MySQLDriver(profile: loopbackProfile(readOnly: true), password: nil)
        var rawInsertRejected = false
        var crudInsertRejected = false
        do {
            _ = try await readonly.query("INSERT INTO \(scratchDB).t (id) VALUES (1)", database: nil)
        } catch {
            rawInsertRejected = true // a READ ONLY session refuses the SQL-runner write server-side
        }
        do {
            // The CRUD path wraps writes in an explicit `START TRANSACTION` — which inherits the
            // session's READ ONLY access mode — so it must be rejected server-side too.
            try await readonly.insert(
                database: scratchDB,
                table: "t",
                values: [ColumnValue(column: "id", value: .int(2))]
            )
        } catch {
            crudInsertRejected = true
        }

        _ = try? await writable.query("DROP DATABASE IF EXISTS \(scratchDB)", database: nil)
        XCTAssertTrue(rawInsertRejected, "read-only session must reject SQL-runner INSERT server-side")
        XCTAssertTrue(crudInsertRejected, "read-only session must reject CRUD insert() server-side")
    }
}
