import CoreGraphics
import Foundation

public struct ERColumn: Sendable, Equatable, Identifiable {
    public let name: String
    public let dataType: String
    public let isPrimaryKey: Bool
    public let isForeignKey: Bool
    public let isNullable: Bool

    public var id: String {
        name
    }

    public init(
        name: String,
        dataType: String,
        isPrimaryKey: Bool,
        isForeignKey: Bool,
        isNullable: Bool
    ) {
        self.name = name
        self.dataType = dataType
        self.isPrimaryKey = isPrimaryKey
        self.isForeignKey = isForeignKey
        self.isNullable = isNullable
    }
}

public struct ERSchemaNode: Sendable, Equatable, Identifiable {
    public let id: String
    public let table: String
    public let columns: [ERColumn]
    public let displayColumns: [ERColumn]

    public init(table: String, columns: [ERColumn], displayColumns: [ERColumn]) {
        id = table
        self.table = table
        self.columns = columns
        self.displayColumns = displayColumns
    }
}

public struct ERSchemaEdge: Sendable, Equatable, Identifiable {
    public let fkName: String
    public let fromTable: String
    public let fromColumn: String
    public let toTable: String
    public let toColumn: String

    public var id: String {
        "\(fromTable).\(fkName).\(fromColumn)->\(toTable).\(toColumn)"
    }

    public init(
        fkName: String,
        fromTable: String,
        fromColumn: String,
        toTable: String,
        toColumn: String
    ) {
        self.fkName = fkName
        self.fromTable = fromTable
        self.fromColumn = fromColumn
        self.toTable = toTable
        self.toColumn = toColumn
    }
}

public struct ERSchemaGraph: Sendable, Equatable {
    public let nodes: [ERSchemaNode]
    public let edges: [ERSchemaEdge]
    public let connectedTables: Set<String>

    public init(nodes: [ERSchemaNode], edges: [ERSchemaEdge]) {
        self.nodes = nodes
        self.edges = edges
        connectedTables = Set(edges.flatMap { [$0.fromTable, $0.toTable] })
    }

    public static let empty = ERSchemaGraph(nodes: [], edges: [])
}

public enum ERSchemaGraphBuilder {
    public static func build(
        detailedColumns: [String: [ColumnInfo]],
        relations: [ForeignKeyRelation],
        compact: Bool
    ) -> ERSchemaGraph {
        var foreignKeyColumnsByTable: [String: Set<String>] = [:]
        for relation in relations {
            foreignKeyColumnsByTable[relation.fromTable, default: []].insert(relation.fromColumn)
        }

        var nodes: [ERSchemaNode] = []
        nodes.reserveCapacity(detailedColumns.count)
        for table in detailedColumns.keys.sorted() {
            let fkColumns = foreignKeyColumnsByTable[table] ?? []
            let columns = (detailedColumns[table] ?? []).map { info in
                ERColumn(
                    name: info.name,
                    dataType: info.dataType,
                    isPrimaryKey: info.isPrimaryKey,
                    isForeignKey: fkColumns.contains(info.name),
                    isNullable: info.isNullable
                )
            }
            let display = displayColumns(from: columns, compact: compact)
            nodes.append(ERSchemaNode(table: table, columns: columns, displayColumns: display))
        }

        let tableNames = Set(nodes.map(\.table))
        var edges: [ERSchemaEdge] = []
        var seen = Set<String>()
        for relation in relations {
            guard tableNames.contains(relation.fromTable),
                  tableNames.contains(relation.toTable) else { continue }
            let key = "\(relation.fromTable).\(relation.fromColumn)->\(relation.toTable).\(relation.toColumn)"
            guard seen.insert(key).inserted else { continue }
            edges.append(ERSchemaEdge(
                fkName: relation.constraintName ?? key,
                fromTable: relation.fromTable,
                fromColumn: relation.fromColumn,
                toTable: relation.toTable,
                toColumn: relation.toColumn
            ))
        }

        return ERSchemaGraph(nodes: nodes, edges: edges)
    }

    private static func displayColumns(from columns: [ERColumn], compact: Bool) -> [ERColumn] {
        guard compact else { return columns }
        let keyed = columns.filter { $0.isPrimaryKey || $0.isForeignKey }
        return keyed.isEmpty ? columns : keyed
    }
}
