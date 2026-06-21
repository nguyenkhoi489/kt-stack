import XCTest
import CoreGraphics
@testable import KTStackKit

final class ERSchemaGraphAndLayoutTests: XCTestCase {

    private func column(_ name: String, pk: Bool = false) -> ColumnInfo {
        ColumnInfo(name: name, dataType: "int", isNullable: false, isPrimaryKey: pk)
    }

    private func relation(_ from: String, _ fromCol: String, _ to: String, _ toCol: String) -> ForeignKeyRelation {
        ForeignKeyRelation(fromTable: from, fromColumn: fromCol, toTable: to, toColumn: toCol)
    }

    func testDetailedColumnsCatalogKeepsRichDataAndNames() {
        let detailed: [String: [ColumnInfo]] = [
            "users": [column("id", pk: true), column("email")]
        ]
        let catalog = SchemaCatalog(tables: ["users"]).withDetailedColumns(detailed)
        XCTAssertEqual(catalog.detailedColumnsByTable["users"]?.map(\.name), ["id", "email"])
        XCTAssertEqual(catalog.columnsByTable["users"], ["id", "email"])
        XCTAssertTrue(catalog.detailedColumnsByTable["users"]?.first?.isPrimaryKey ?? false)
    }

    func testBuilderMarksForeignKeyColumns() {
        let detailed: [String: [ColumnInfo]] = [
            "posts": [column("id", pk: true), column("user_id")],
            "users": [column("id", pk: true)]
        ]
        let graph = ERSchemaGraphBuilder.build(
            detailedColumns: detailed,
            relations: [relation("posts", "user_id", "users", "id")],
            compact: false)
        let posts = graph.nodes.first { $0.table == "posts" }
        XCTAssertTrue(posts?.columns.first { $0.name == "user_id" }?.isForeignKey ?? false)
        XCTAssertEqual(graph.edges.count, 1)
    }

    func testCompactModeKeepsOnlyKeyColumns() {
        let detailed: [String: [ColumnInfo]] = [
            "posts": [column("id", pk: true), column("title"), column("user_id")],
            "users": [column("id", pk: true)]
        ]
        let graph = ERSchemaGraphBuilder.build(
            detailedColumns: detailed,
            relations: [relation("posts", "user_id", "users", "id")],
            compact: true)
        let posts = graph.nodes.first { $0.table == "posts" }
        XCTAssertEqual(posts?.displayColumns.map(\.name), ["id", "user_id"])
        XCTAssertEqual(posts?.columns.count, 3)
    }

    func testCyclicGraphDoesNotCrashAndPlacesAllNodes() {
        let detailed: [String: [ColumnInfo]] = [
            "a": [column("id", pk: true)],
            "b": [column("id", pk: true)],
            "c": [column("id", pk: true)]
        ]
        let graph = ERSchemaGraphBuilder.build(
            detailedColumns: detailed,
            relations: [
                relation("a", "id", "b", "id"),
                relation("b", "id", "c", "id"),
                relation("c", "id", "a", "id")
            ],
            compact: false)
        let positions = ERSugiyamaLayout.compute(graph: graph)
        XCTAssertEqual(Set(positions.keys), ["a", "b", "c"])
    }

    func testLinearForeignKeyChainProducesIncreasingLayers() {
        let detailed: [String: [ColumnInfo]] = [
            "a": [column("id", pk: true)],
            "b": [column("id", pk: true)],
            "c": [column("id", pk: true)]
        ]
        let graph = ERSchemaGraphBuilder.build(
            detailedColumns: detailed,
            relations: [
                relation("a", "id", "b", "id"),
                relation("b", "id", "c", "id")
            ],
            compact: false)
        let positions = ERSugiyamaLayout.compute(graph: graph)
        let ay = positions["a"]!.y
        let by = positions["b"]!.y
        let cy = positions["c"]!.y
        XCTAssertLessThan(ay, by)
        XCTAssertLessThan(by, cy)
    }

    func testIsolatedNodesPlacedBelowConnectedLayers() {
        let detailed: [String: [ColumnInfo]] = [
            "a": [column("id", pk: true)],
            "b": [column("id", pk: true)],
            "lonely": [column("id", pk: true)]
        ]
        let graph = ERSchemaGraphBuilder.build(
            detailedColumns: detailed,
            relations: [relation("a", "id", "b", "id")],
            compact: false)
        let positions = ERSugiyamaLayout.compute(graph: graph)
        let maxConnectedY = max(positions["a"]!.y, positions["b"]!.y)
        XCTAssertGreaterThan(positions["lonely"]!.y, maxConnectedY)
    }

    func testLayoutIsDeterministic() {
        let detailed: [String: [ColumnInfo]] = [
            "a": [column("id", pk: true)],
            "b": [column("id", pk: true)],
            "c": [column("id", pk: true)]
        ]
        let relations = [relation("a", "id", "b", "id"), relation("b", "id", "c", "id")]
        let graph = ERSchemaGraphBuilder.build(detailedColumns: detailed, relations: relations, compact: false)
        let first = ERSugiyamaLayout.compute(graph: graph)
        let second = ERSugiyamaLayout.compute(graph: graph)
        XCTAssertEqual(first, second)
    }

    func testRectIndexCentersRectsOnPositions() {
        let detailed: [String: [ColumnInfo]] = ["a": [column("id", pk: true), column("name")]]
        let graph = ERSchemaGraphBuilder.build(detailedColumns: detailed, relations: [], compact: false)
        let positions = ERSugiyamaLayout.compute(graph: graph)
        let rects = ERRectIndex.rects(positions: positions, nodes: graph.nodes)
        let rect = rects["a"]!
        XCTAssertEqual(rect.midX, positions["a"]!.x, accuracy: 0.01)
        XCTAssertEqual(rect.width, ERSugiyamaLayout.nodeWidth, accuracy: 0.01)
    }
}
