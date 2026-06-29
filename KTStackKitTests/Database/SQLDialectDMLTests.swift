import XCTest
@testable import KTStackKit

/// Engine-free coverage of parameterized DML composition — CI-blocking. Identifiers are quoted
/// (injection defense), values ride as ordered binds (never interpolated), and the keyless-write
/// guard is a data-integrity boundary the dialect enforces before any SQL reaches a server.
final class SQLDialectDMLTests: XCTestCase {
    private let d = SQLDialect.forKind(.mysql)

    func testInsertQuotesColumnsAndOrdersBinds() throws {
        let stmt = try d.insert(schema: "app", table: "users", values: [
            ColumnValue(column: "name", value: .text("Khoi")),
            ColumnValue(column: "age", value: .int(30)),
        ])
        XCTAssertEqual(stmt.sql, "INSERT INTO `app`.`users` (`name`, `age`) VALUES (?, ?)")
        XCTAssertEqual(stmt.binds, [.text("Khoi"), .int(30)])
    }

    func testUpdateBindsValuesThenCompositeKey() throws {
        let stmt = try d.update(
            schema: "app",
            table: "user",
            values: [ColumnValue(column: "email", value: .text("a@b.c"))],
            key: [
                ColumnValue(column: "Host", value: .text("localhost")),
                ColumnValue(column: "User", value: .text("root")),
            ]
        )
        XCTAssertEqual(
            stmt.sql,
            "UPDATE `app`.`user` SET `email` = ? WHERE `Host` = ? AND `User` = ?"
        )
        // SET values first, then key values — positional with the placeholders.
        XCTAssertEqual(stmt.binds, [.text("a@b.c"), .text("localhost"), .text("root")])
    }

    func testDeleteBuildsCompositeKeyWhere() throws {
        let stmt = try d.delete(schema: "app", table: "t", key: [
            ColumnValue(column: "a", value: .int(1)),
            ColumnValue(column: "b", value: .int(2)),
        ])
        XCTAssertEqual(stmt.sql, "DELETE FROM `app`.`t` WHERE `a` = ? AND `b` = ?")
        XCTAssertEqual(stmt.binds, [.int(1), .int(2)])
    }

    func testEmptyValuesRejected() {
        XCTAssertThrowsError(try d.insert(schema: "a", table: "t", values: []))
        XCTAssertThrowsError(try d.update(
            schema: "a",
            table: "t",
            values: [],
            key: [ColumnValue(column: "id", value: .int(1))]
        ))
    }

    func testKeylessWriteRejected() {
        // A keyless UPDATE/DELETE would touch every row — the dialect never emits one.
        XCTAssertThrowsError(try d.update(
            schema: "a",
            table: "t",
            values: [ColumnValue(column: "x", value: .int(1))],
            key: []
        ))
        XCTAssertThrowsError(try d.delete(schema: "a", table: "t", key: []))
    }

    func testNullKeyRejected() {
        // `col = NULL` never matches — a NULL key can't identify a row.
        XCTAssertThrowsError(try d.delete(
            schema: "a",
            table: "t",
            key: [ColumnValue(column: "id", value: .null)]
        ))
    }

    func testIdentifierInjectionInColumnIsNeutralized() throws {
        // A column name with a backtick is doubled, not allowed to break out.
        let stmt = try d.insert(
            schema: "a",
            table: "t",
            values: [ColumnValue(column: "ev`il", value: .text("x"))]
        )
        XCTAssertEqual(stmt.sql, "INSERT INTO `a`.`t` (`ev``il`) VALUES (?)")
    }
}
