import XCTest
import CoreGraphics
@testable import KDWarmKit

final class ERLayoutEngineTests: XCTestCase {

    func testEmptyTablesProducesEmptyLayout() {
        let layout = ERLayoutEngine.layout(tables: [], columnsByTable: [:], relations: [])
        XCTAssertEqual(layout, ERDiagramLayout.empty)
    }

    func testLayoutIsDeterministicForSameInput() {
        let tables = ["orders", "users", "items"]
        let cols: [String: [String]] = [
            "users": ["id", "name"],
            "orders": ["id", "user_id"],
            "items": ["id", "order_id"]
        ]
        let relations = [
            ForeignKeyRelation(fromTable: "orders", fromColumn: "user_id", toTable: "users", toColumn: "id"),
            ForeignKeyRelation(fromTable: "items", fromColumn: "order_id", toTable: "orders", toColumn: "id")
        ]
        let a = ERLayoutEngine.layout(tables: tables, columnsByTable: cols, relations: relations)
        let b = ERLayoutEngine.layout(tables: tables, columnsByTable: cols, relations: relations)
        XCTAssertEqual(a, b)
    }

    func testNodesDoNotOverlap() {
        let tables = (1...6).map { "t\($0)" }
        let cols = Dictionary(uniqueKeysWithValues: tables.map { ($0, ["id", "name", "value"]) })
        let layout = ERLayoutEngine.layout(tables: tables, columnsByTable: cols, relations: [])
        let rects = layout.nodes.map(\.rect)
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                XCTAssertFalse(rects[i].intersects(rects[j]),
                                "Node \(i) overlaps node \(j): \(rects[i]) vs \(rects[j])")
            }
        }
    }

    func testEdgesConnectExistingNodes() {
        let tables = ["users", "orders"]
        let cols: [String: [String]] = [
            "users": ["id"],
            "orders": ["id", "user_id"]
        ]
        let relations = [
            ForeignKeyRelation(fromTable: "orders", fromColumn: "user_id", toTable: "users", toColumn: "id")
        ]
        let layout = ERLayoutEngine.layout(tables: tables, columnsByTable: cols, relations: relations)
        XCTAssertEqual(layout.edges.count, 1)
        let edge = try! XCTUnwrap(layout.edges.first)
        XCTAssertEqual(edge.fromTable, "orders")
        XCTAssertEqual(edge.toTable, "users")

        let fromRect = layout.nodes.first { $0.table == "orders" }!.rect
        let toRect = layout.nodes.first { $0.table == "users" }!.rect
        let onFromBorder = abs(edge.fromPoint.x - fromRect.minX) < 0.01
            || abs(edge.fromPoint.x - fromRect.maxX) < 0.01
            || abs(edge.fromPoint.y - fromRect.minY) < 0.01
            || abs(edge.fromPoint.y - fromRect.maxY) < 0.01
        let onToBorder = abs(edge.toPoint.x - toRect.minX) < 0.01
            || abs(edge.toPoint.x - toRect.maxX) < 0.01
            || abs(edge.toPoint.y - toRect.minY) < 0.01
            || abs(edge.toPoint.y - toRect.maxY) < 0.01
        XCTAssertTrue(onFromBorder)
        XCTAssertTrue(onToBorder)
    }

    func testCompositeFKCollapsesToSingleEdge() {
        let tables = ["parent", "child"]
        let cols: [String: [String]] = [
            "parent": ["a", "b"],
            "child": ["pa", "pb"]
        ]
        let relations = [
            ForeignKeyRelation(fromTable: "child", fromColumn: "pa", toTable: "parent", toColumn: "a"),
            ForeignKeyRelation(fromTable: "child", fromColumn: "pb", toTable: "parent", toColumn: "b")
        ]
        let layout = ERLayoutEngine.layout(tables: tables, columnsByTable: cols, relations: relations)
        XCTAssertEqual(layout.edges.count, 1)
    }

    func testRelationsToMissingTablesAreIgnored() {
        let layout = ERLayoutEngine.layout(
            tables: ["users"],
            columnsByTable: ["users": ["id"]],
            relations: [
                ForeignKeyRelation(fromTable: "ghost", fromColumn: "u", toTable: "users", toColumn: "id")
            ])
        XCTAssertEqual(layout.edges.count, 0)
    }

    func testForeignKeyColumnsAreMarked() {
        let layout = ERLayoutEngine.layout(
            tables: ["orders"],
            columnsByTable: ["orders": ["id", "user_id"]],
            relations: [
                ForeignKeyRelation(fromTable: "orders", fromColumn: "user_id", toTable: "users", toColumn: "id")
            ])
        let node = try! XCTUnwrap(layout.nodes.first)
        XCTAssertTrue(node.foreignKeyColumns.contains("user_id"))
        XCTAssertFalse(node.foreignKeyColumns.contains("id"))
    }
}
