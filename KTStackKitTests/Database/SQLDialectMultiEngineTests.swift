import XCTest
@testable import KTStackKit

/// Engine-free coverage that the per-kind dialect spells placeholders, quoting and pagination right
/// for every relational engine — CI-blocking. Placeholder numbering is a correctness boundary: a
/// PostgreSQL UPDATE binds SET values then WHERE keys, so the `$N` indices must run continuously
/// across both clauses to line up with `binds` (values + key).
final class SQLDialectMultiEngineTests: XCTestCase {
    private func col(_ name: String, _ value: Cell) -> ColumnValue {
        ColumnValue(column: name, value: value)
    }

    func testPostgresInsertUsesDollarPlaceholders() throws {
        let d = SQLDialect.forKind(.postgres)
        let stmt = try d.insert(
            schema: "public",
            table: "users",
            values: [col("name", .text("a")), col("age", .int(1))]
        )
        XCTAssertEqual(
            stmt.sql,
            #"INSERT INTO "public"."users" ("name", "age") VALUES ($1, $2)"#
        )
        XCTAssertEqual(stmt.binds, [.text("a"), .int(1)])
    }

    func testPostgresUpdateNumbersSetThenWhereContinuously() throws {
        let d = SQLDialect.forKind(.postgres)
        let stmt = try d.update(
            schema: "public",
            table: "t",
            values: [col("a", .int(1)), col("b", .int(2))],
            key: [col("id", .int(9))]
        )
        XCTAssertEqual(
            stmt.sql,
            #"UPDATE "public"."t" SET "a" = $1, "b" = $2 WHERE "id" = $3"#
        )
        XCTAssertEqual(stmt.binds, [.int(1), .int(2), .int(9)])
    }

    func testPostgresDeleteUsesDollarPlaceholders() throws {
        let d = SQLDialect.forKind(.postgres)
        let stmt = try d.delete(
            schema: "public",
            table: "t",
            key: [col("h", .text("x")), col("u", .text("y"))]
        )
        XCTAssertEqual(stmt.sql, #"DELETE FROM "public"."t" WHERE "h" = $1 AND "u" = $2"#)
    }

    func testSQLiteInsertUsesQuestionPlaceholdersAndDoubleQuotes() throws {
        let d = SQLDialect.forKind(.sqlite)
        let stmt = try d.insert(schema: "main", table: "notes", values: [col("body", .text("hi"))])
        XCTAssertEqual(stmt.sql, #"INSERT INTO "main"."notes" ("body") VALUES (?)"#)
    }

    func testSQLiteUpdateUsesQuestionPlaceholders() throws {
        let d = SQLDialect.forKind(.sqlite)
        let stmt = try d.update(
            schema: "main",
            table: "t",
            values: [col("a", .int(1))],
            key: [col("id", .int(2))]
        )
        XCTAssertEqual(stmt.sql, #"UPDATE "main"."t" SET "a" = ? WHERE "id" = ?"#)
    }

    func testMySQLInsertStillUsesQuestionPlaceholders() throws {
        let d = SQLDialect.forKind(.mysql)
        let stmt = try d.insert(schema: "app", table: "users", values: [col("name", .text("a"))])
        XCTAssertEqual(stmt.sql, "INSERT INTO `app`.`users` (`name`) VALUES (?)")
    }

    func testPaginationIsLimitOffsetForEveryEngine() {
        for kind in [DatabaseKind.mysql, .postgres, .sqlite] {
            let d = SQLDialect.forKind(kind)
            XCTAssertEqual(
                d.paginate("SELECT 1", limit: 10, offset: 20),
                "SELECT 1 LIMIT 10 OFFSET 20",
                "engine \(kind)"
            )
        }
    }
}
