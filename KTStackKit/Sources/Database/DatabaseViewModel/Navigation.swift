import Foundation

public struct BreadcrumbEntry: Equatable, Identifiable {
    public let id = UUID()
    public let table: TableInfo
    public let filters: [FilterCondition]
    public let sort: SortSpec?

    public init(table: TableInfo, filters: [FilterCondition], sort: SortSpec?) {
        self.table = table
        self.filters = filters
        self.sort = sort
    }

    public static func == (lhs: BreadcrumbEntry, rhs: BreadcrumbEntry) -> Bool {
        lhs.id == rhs.id
    }
}

public extension DatabaseViewModel {
    func navigableForeignKeys(forTable table: String) -> [String: ForeignKeyRelation] {
        let relations = schemaCatalog.relations.filter { $0.fromTable == table }
        var membersByConstraint: [String: Int] = [:]
        for relation in relations {
            membersByConstraint[constraintKey(relation), default: 0] += 1
        }
        var byColumn: [String: ForeignKeyRelation] = [:]
        for relation in relations {
            guard membersByConstraint[constraintKey(relation)] == 1 else { continue }
            guard schemaCatalog.tables.contains(relation.toTable) else { continue }
            byColumn[relation.fromColumn] = relation
        }
        return byColumn
    }

    func navigateForeignKey(fromColumn: String, value: Cell) async {
        guard value != .null else { return }
        guard let table = selectedTable,
              let relation = navigableForeignKeys(forTable: table.name)[fromColumn] else { return }
        navigationStack.append(BreadcrumbEntry(table: table, filters: activeFilters, sort: activeSort))
        await loadSelectedTable(
            TableInfo(name: relation.toTable),
            filters: [FilterCondition(column: relation.toColumn, op: .equals, value: value)],
            sort: nil
        )
    }

    func popNavigation() async {
        guard let entry = navigationStack.popLast() else { return }
        await loadSelectedTable(entry.table, filters: entry.filters, sort: entry.sort)
    }

    private func constraintKey(_ relation: ForeignKeyRelation) -> String {
        relation.constraintName
            ?? "\(relation.fromColumn)->\(relation.toTable).\(relation.toColumn)"
    }
}
