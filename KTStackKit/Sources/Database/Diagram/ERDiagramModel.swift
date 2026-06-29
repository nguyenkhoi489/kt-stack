import CoreGraphics
import Foundation

public struct ERTableNode: Sendable, Equatable, Identifiable {
    public let table: String
    public let columns: [String]
    public let primaryKeyColumns: Set<String>
    public let foreignKeyColumns: Set<String>
    public let rect: CGRect

    public var id: String {
        table
    }

    public init(
        table: String,
        columns: [String],
        primaryKeyColumns: Set<String> = [],
        foreignKeyColumns: Set<String> = [],
        rect: CGRect
    ) {
        self.table = table
        self.columns = columns
        self.primaryKeyColumns = primaryKeyColumns
        self.foreignKeyColumns = foreignKeyColumns
        self.rect = rect
    }
}

public struct EREdge: Sendable, Equatable, Identifiable {
    public let fromTable: String
    public let toTable: String
    public let fromPoint: CGPoint
    public let toPoint: CGPoint

    public var id: String {
        "\(fromTable)->\(toTable)"
    }

    public init(fromTable: String, toTable: String, fromPoint: CGPoint, toPoint: CGPoint) {
        self.fromTable = fromTable
        self.toTable = toTable
        self.fromPoint = fromPoint
        self.toPoint = toPoint
    }
}

public struct ERDiagramLayout: Sendable, Equatable {
    public let nodes: [ERTableNode]
    public let edges: [EREdge]
    public let canvasSize: CGSize

    public init(nodes: [ERTableNode], edges: [EREdge], canvasSize: CGSize) {
        self.nodes = nodes
        self.edges = edges
        self.canvasSize = canvasSize
    }

    public static let empty = ERDiagramLayout(nodes: [], edges: [], canvasSize: .zero)
}
