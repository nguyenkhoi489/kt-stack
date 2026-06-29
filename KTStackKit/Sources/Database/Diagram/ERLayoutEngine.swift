import CoreGraphics
import Foundation

public enum ERLayoutEngine {
    public struct Config: Sendable, Equatable {
        public let nodeWidth: CGFloat
        public let headerHeight: CGFloat
        public let rowHeight: CGFloat
        public let columnsPerRow: Int
        public let horizontalSpacing: CGFloat
        public let verticalSpacing: CGFloat
        public let padding: CGFloat

        public init(
            nodeWidth: CGFloat = 220,
            headerHeight: CGFloat = 28,
            rowHeight: CGFloat = 18,
            columnsPerRow: Int = 4,
            horizontalSpacing: CGFloat = 60,
            verticalSpacing: CGFloat = 40,
            padding: CGFloat = 40
        ) {
            self.nodeWidth = nodeWidth
            self.headerHeight = headerHeight
            self.rowHeight = rowHeight
            self.columnsPerRow = columnsPerRow
            self.horizontalSpacing = horizontalSpacing
            self.verticalSpacing = verticalSpacing
            self.padding = padding
        }

        public static let `default` = Config()
    }

    public static func layout(
        tables: [String],
        columnsByTable: [String: [String]],
        primaryKeysByTable: [String: Set<String>] = [:],
        relations: [ForeignKeyRelation],
        config: Config = .default
    ) -> ERDiagramLayout {
        guard !tables.isEmpty else { return .empty }

        let ordered = orderTables(tables, relations: relations)
        let fksByTable = foreignKeyColumns(relations: relations)
        let cardinality = relationCount(relations: relations, tables: Set(ordered))
        let sorted = ordered.sorted { lhs, rhs in
            let lcount = cardinality[lhs] ?? 0
            let rcount = cardinality[rhs] ?? 0
            if lcount != rcount { return lcount > rcount }
            return lhs < rhs
        }

        let columnsPerRow = max(1, config.columnsPerRow)
        let rowsCount = (sorted.count + columnsPerRow - 1) / columnsPerRow
        var rowHeights: [CGFloat] = []
        rowHeights.reserveCapacity(rowsCount)
        for rowIndex in 0..<rowsCount {
            let start = rowIndex * columnsPerRow
            let end = min(start + columnsPerRow, sorted.count)
            var maxHeight: CGFloat = 0
            for index in start..<end {
                let cols = columnsByTable[sorted[index]] ?? []
                let height = nodeHeight(columnCount: cols.count, config: config)
                if height > maxHeight { maxHeight = height }
            }
            rowHeights.append(maxHeight)
        }

        var rowOriginsY: [CGFloat] = []
        rowOriginsY.reserveCapacity(rowsCount)
        var cursorY = config.padding
        for height in rowHeights {
            rowOriginsY.append(cursorY)
            cursorY += height + config.verticalSpacing
        }
        let canvasHeight = cursorY - config.verticalSpacing + config.padding

        var nodes: [ERTableNode] = []
        var rectsByTable: [String: CGRect] = [:]
        nodes.reserveCapacity(sorted.count)

        for (index, table) in sorted.enumerated() {
            let row = index / columnsPerRow
            let col = index % columnsPerRow
            let originX = config.padding + CGFloat(col) * (config.nodeWidth + config.horizontalSpacing)
            let originY = rowOriginsY[row]
            let cols = columnsByTable[table] ?? []
            let height = nodeHeight(columnCount: cols.count, config: config)
            let rect = CGRect(x: originX, y: originY, width: config.nodeWidth, height: height)
            rectsByTable[table] = rect
            nodes.append(ERTableNode(
                table: table,
                columns: cols,
                primaryKeyColumns: primaryKeysByTable[table] ?? [],
                foreignKeyColumns: fksByTable[table] ?? [],
                rect: rect
            ))
        }

        let canvasWidth = config.padding * 2
            + CGFloat(min(sorted.count, columnsPerRow)) * config.nodeWidth
            + CGFloat(max(0, min(sorted.count, columnsPerRow) - 1)) * config.horizontalSpacing

        let edges = buildEdges(relations: relations, rectsByTable: rectsByTable)

        return ERDiagramLayout(
            nodes: nodes,
            edges: edges,
            canvasSize: CGSize(width: canvasWidth, height: canvasHeight)
        )
    }

    private static func nodeHeight(columnCount: Int, config: Config) -> CGFloat {
        config.headerHeight + CGFloat(max(1, columnCount)) * config.rowHeight + 8
    }

    private static func relationCount(
        relations: [ForeignKeyRelation],
        tables: Set<String>
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for rel in relations where tables.contains(rel.fromTable) && tables.contains(rel.toTable) {
            counts[rel.fromTable, default: 0] += 1
            counts[rel.toTable, default: 0] += 1
        }
        return counts
    }

    private static func foreignKeyColumns(relations: [ForeignKeyRelation]) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for rel in relations {
            map[rel.fromTable, default: []].insert(rel.fromColumn)
        }
        return map
    }

    private static func orderTables(_ tables: [String], relations _: [ForeignKeyRelation]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for name in tables where seen.insert(name).inserted {
            ordered.append(name)
        }
        return ordered
    }

    private static func buildEdges(
        relations: [ForeignKeyRelation],
        rectsByTable: [String: CGRect]
    ) -> [EREdge] {
        var seen = Set<String>()
        var edges: [EREdge] = []
        for rel in relations {
            guard let fromRect = rectsByTable[rel.fromTable],
                  let toRect = rectsByTable[rel.toTable]
            else { continue }
            let key = "\(rel.fromTable)|\(rel.toTable)"
            guard seen.insert(key).inserted else { continue }
            let (fromPoint, toPoint) = anchorPoints(from: fromRect, to: toRect)
            edges.append(EREdge(
                fromTable: rel.fromTable,
                toTable: rel.toTable,
                fromPoint: fromPoint,
                toPoint: toPoint
            ))
        }
        return edges
    }

    private static func anchorPoints(from: CGRect, to: CGRect) -> (CGPoint, CGPoint) {
        let fromCenter = CGPoint(x: from.midX, y: from.midY)
        let toCenter = CGPoint(x: to.midX, y: to.midY)
        let fromPoint: CGPoint
        let toPoint: CGPoint
        if abs(fromCenter.x - toCenter.x) >= abs(fromCenter.y - toCenter.y) {
            if fromCenter.x <= toCenter.x {
                fromPoint = CGPoint(x: from.maxX, y: from.midY)
                toPoint = CGPoint(x: to.minX, y: to.midY)
            } else {
                fromPoint = CGPoint(x: from.minX, y: from.midY)
                toPoint = CGPoint(x: to.maxX, y: to.midY)
            }
        } else {
            if fromCenter.y <= toCenter.y {
                fromPoint = CGPoint(x: from.midX, y: from.maxY)
                toPoint = CGPoint(x: to.midX, y: to.minY)
            } else {
                fromPoint = CGPoint(x: from.midX, y: from.minY)
                toPoint = CGPoint(x: to.midX, y: to.maxY)
            }
        }
        return (fromPoint, toPoint)
    }
}
