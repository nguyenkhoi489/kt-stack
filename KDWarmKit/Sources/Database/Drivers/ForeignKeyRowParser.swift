import Foundation

public enum ForeignKeyRowParser {

    public static func parseRelational(_ rows: [[Cell]]) -> [ForeignKeyRelation] {
        rows.compactMap { row in
            guard row.count >= 4,
                  let fromTable = row[0].displayText, !fromTable.isEmpty,
                  let fromColumn = row[1].displayText, !fromColumn.isEmpty,
                  let toTable = row[2].displayText, !toTable.isEmpty,
                  let toColumn = row[3].displayText, !toColumn.isEmpty
            else { return nil }
            let name = row.count >= 5 ? row[4].displayText : nil
            return ForeignKeyRelation(fromTable: fromTable,
                                       fromColumn: fromColumn,
                                       toTable: toTable,
                                       toColumn: toColumn,
                                       constraintName: name?.isEmpty == false ? name : nil)
        }
    }
}
