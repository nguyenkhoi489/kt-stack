import XCTest
@testable import KTStackKit

final class SQLDialectBrowseSelectTests: XCTestCase {
    private let mysql = SQLDialect.forKind(.mysql)
    private let postgres = SQLDialect.forKind(.postgres)

    func testPlainBrowseSelectHasNoWhereOrOrderBy() throws {
        let stmt = try mysql.browseSelect(
            schema: "db",
            table: "t",
            filters: [],
            sort: nil,
            limit: 100,
            offset: 0
        )
        XCTAssertEqual(stmt.sql, "SELECT * FROM `db`.`t` LIMIT 100 OFFSET 0")
        XCTAssertTrue(stmt.binds.isEmpty)
    }

    func testEqualsFilterBindsTheValue() throws {
        let stmt = try mysql.browseSelect(
            schema: "db", table: "users",
            filters: [FilterCondition(column: "name", op: .equals, value: .text("ann"))],
            sort: nil, limit: 50, offset: 10
        )
        XCTAssertEqual(stmt.sql, "SELECT * FROM `db`.`users` WHERE `name` = ? LIMIT 50 OFFSET 10")
        XCTAssertEqual(stmt.binds, [.text("ann")])
    }

    func testNullOperatorsDoNotBind() throws {
        let stmt = try mysql.browseSelect(
            schema: "db", table: "t",
            filters: [
                FilterCondition(column: "a", op: .isNull),
                FilterCondition(column: "b", op: .isNotNull),
            ],
            sort: nil, limit: 100, offset: 0
        )
        XCTAssertEqual(
            stmt.sql,
            "SELECT * FROM `db`.`t` WHERE `a` IS NULL AND `b` IS NOT NULL LIMIT 100 OFFSET 0"
        )
        XCTAssertTrue(stmt.binds.isEmpty)
    }

    func testContainsWrapsValueInWildcards() throws {
        let stmt = try mysql.browseSelect(
            schema: "db", table: "t",
            filters: [FilterCondition(column: "name", op: .contains, value: .text("li"))],
            sort: nil, limit: 100, offset: 0
        )
        XCTAssertEqual(stmt.sql, "SELECT * FROM `db`.`t` WHERE `name` LIKE ? LIMIT 100 OFFSET 0")
        XCTAssertEqual(stmt.binds, [.text("%li%")])
    }

    func testMultipleFiltersAreAndCombinedWithSequentialPlaceholders() throws {
        let stmt = try postgres.browseSelect(
            schema: "public", table: "orders",
            filters: [
                FilterCondition(column: "status", op: .equals, value: .text("paid")),
                FilterCondition(column: "total", op: .greaterThan, value: .int(100)),
            ],
            sort: nil, limit: 25, offset: 0
        )
        XCTAssertEqual(
            stmt.sql,
            "SELECT * FROM \"public\".\"orders\" WHERE \"status\" = $1 AND \"total\" > $2 LIMIT 25 OFFSET 0"
        )
        XCTAssertEqual(stmt.binds, [.text("paid"), .int(100)])
    }

    func testSortDirectionIsAnEmittedLiteral() throws {
        let asc = try mysql.browseSelect(
            schema: "db",
            table: "t",
            filters: [],
            sort: SortSpec(column: "name", ascending: true),
            limit: 10,
            offset: 0
        )
        XCTAssertEqual(asc.sql, "SELECT * FROM `db`.`t` ORDER BY `name` ASC LIMIT 10 OFFSET 0")

        let desc = try mysql.browseSelect(
            schema: "db",
            table: "t",
            filters: [],
            sort: SortSpec(column: "name", ascending: false),
            limit: 10,
            offset: 0
        )
        XCTAssertEqual(desc.sql, "SELECT * FROM `db`.`t` ORDER BY `name` DESC LIMIT 10 OFFSET 0")
    }

    func testFilterAndSortCombine() throws {
        let stmt = try mysql.browseSelect(
            schema: "db", table: "t",
            filters: [FilterCondition(column: "age", op: .lessThan, value: .int(30))],
            sort: SortSpec(column: "age", ascending: false), limit: 100, offset: 0
        )
        XCTAssertEqual(
            stmt.sql,
            "SELECT * FROM `db`.`t` WHERE `age` < ? ORDER BY `age` DESC LIMIT 100 OFFSET 0"
        )
        XCTAssertEqual(stmt.binds, [.int(30)])
    }

    func testMaliciousValueGoesToBindsNotSQL() throws {
        let evil = "x'; DROP TABLE users;--"
        let stmt = try mysql.browseSelect(
            schema: "db", table: "t",
            filters: [FilterCondition(column: "name", op: .equals, value: .text(evil))],
            sort: nil, limit: 100, offset: 0
        )
        XCTAssertFalse(stmt.sql.contains("DROP"))
        XCTAssertEqual(stmt.binds, [.text(evil)])
    }

    func testLimitAndOffsetAreClampedToSafeValues() throws {
        let stmt = try mysql.browseSelect(
            schema: "db",
            table: "t",
            filters: [],
            sort: nil,
            limit: 0,
            offset: -5
        )
        XCTAssertEqual(stmt.sql, "SELECT * FROM `db`.`t` LIMIT 1 OFFSET 0")
    }
}
