import XCTest
@testable import KTStackKit

/// Engine-free coverage of DDL composition — CI-blocking. Identifiers route through `quoteIdent`
/// (the injection boundary), and column types route through `sanitizeType` (raw types can't be
/// bound, so the charset restriction is the only thing stopping a type string from extending DDL).
final class SQLDialectDDLTests: XCTestCase {
    private let d = SQLDialect.forKind(.mysql)

    func testCreateTableQuotesIdentifiersAndPrimaryKey() throws {
        let sql = try d.createTable(schema: "app", table: "users", columns: [
            ColumnDefinition(name: "id", type: "INT", isNullable: false, isPrimaryKey: true),
            ColumnDefinition(name: "email", type: "VARCHAR(255)", isNullable: false),
            ColumnDefinition(name: "bio", type: "TEXT", isNullable: true),
        ])
        XCTAssertEqual(
            sql,
            "CREATE TABLE `app`.`users` (`id` INT NOT NULL, `email` VARCHAR(255) NOT NULL, "
                + "`bio` TEXT, PRIMARY KEY (`id`))"
        )
    }

    func testCreateTableSupportsCompositePrimaryKey() throws {
        let sql = try d.createTable(schema: "app", table: "grant", columns: [
            ColumnDefinition(name: "host", type: "VARCHAR(60)", isNullable: false, isPrimaryKey: true),
            ColumnDefinition(name: "user", type: "VARCHAR(32)", isNullable: false, isPrimaryKey: true),
        ])
        XCTAssertEqual(
            sql,
            "CREATE TABLE `app`.`grant` (`host` VARCHAR(60) NOT NULL, `user` VARCHAR(32) NOT NULL, "
                + "PRIMARY KEY (`host`, `user`))"
        )
    }

    func testCreateTableRejectsEmptyColumns() {
        XCTAssertThrowsError(try d.createTable(schema: "a", table: "t", columns: []))
    }

    func testAddColumnComposesAlter() throws {
        let sql = try d.addColumn(
            schema: "app",
            table: "users",
            column: ColumnDefinition(name: "age", type: "INT", isNullable: true)
        )
        XCTAssertEqual(sql, "ALTER TABLE `app`.`users` ADD COLUMN `age` INT")
    }

    func testDropColumnQuotesIdentifier() throws {
        let sql = try d.dropColumn(schema: "app", table: "users", column: "ev`il")
        XCTAssertEqual(sql, "ALTER TABLE `app`.`users` DROP COLUMN `ev``il`")
    }

    func testDropTableQualifies() throws {
        XCTAssertEqual(
            try d.dropTable(schema: "app", table: "users"),
            "DROP TABLE `app`.`users`"
        )
    }

    func testInjectionInTableNameIsNeutralized() throws {
        let sql = try d.createTable(
            schema: "a",
            table: "t`; DROP TABLE x;--",
            columns: [ColumnDefinition(name: "c", type: "INT")]
        )
        // The backtick is doubled, so the payload stays inside the quoted identifier.
        XCTAssertTrue(sql.contains("`t``; DROP TABLE x;--`"))
    }

    func testControlCharInColumnNameRejected() {
        XCTAssertThrowsError(try d.createTable(
            schema: "a",
            table: "t",
            columns: [ColumnDefinition(name: "a\nb", type: "INT")]
        ))
        XCTAssertThrowsError(try d.createTable(
            schema: "a",
            table: "t",
            columns: [ColumnDefinition(name: "a\u{0}b", type: "INT")]
        ))
    }

    func testSanitizeTypeAllowsCommonTypes() throws {
        XCTAssertEqual(try SQLDialect.sanitizeType("  VARCHAR(255) "), "VARCHAR(255)")
        XCTAssertEqual(try SQLDialect.sanitizeType("DECIMAL(10,2) UNSIGNED"), "DECIMAL(10,2) UNSIGNED")
    }

    func testSanitizeTypeRejectsInjectionAndEmpty() {
        XCTAssertThrowsError(try SQLDialect.sanitizeType(""))
        XCTAssertThrowsError(try SQLDialect.sanitizeType("INT; DROP TABLE x")) // semicolon
        XCTAssertThrowsError(try SQLDialect.sanitizeType("INT`")) // backtick
        XCTAssertThrowsError(try SQLDialect.sanitizeType("INT DEFAULT 'x'")) // quote
    }
}
