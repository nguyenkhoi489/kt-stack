import Foundation

public extension DatabaseV2ViewModel {
    var canEdit: Bool {
        !columns.primaryKeyColumns.isEmpty
    }

    var editableColumns: Set<String> {
        guard canEdit else { return [] }
        let pkNames = Set(columns.primaryKeyColumns.map(\.name))
        return Set(columns.map(\.name)).subtracting(pkNames)
    }

    func updateCell(row: Int, column: Int, newValue: String) async {
        guard let result = rows,
              row >= 0, row < result.rows.count,
              column >= 0, column < result.columns.count else { return }
        let columnName = result.columns[column].name
        guard let columnInfo = columns.first(where: { $0.name == columnName }) else { return }
        let value = inlineCell(for: newValue, column: columnInfo)
        guard value != result.rows[row][column] else { return }
        guard let key = keyForRow(row) else {
            editError = "Can't identify this row to update (no primary key)."
            return
        }
        guard let driver, let database = selectedDatabase, let table = selectedTable else { return }
        let token = generation
        editError = nil
        do {
            try await driver.update(
                database: database,
                table: table.name,
                values: [ColumnValue(column: columnName, value: value)],
                key: key
            )
            guard token == generation else { return }
            await reloadCurrentPage()
        } catch {
            guard token == generation else { return }
            editError = error.localizedDescription
        }
    }

    func insertRow(_ values: [ColumnValue]) async {
        guard let driver, let database = selectedDatabase, let table = selectedTable else { return }
        let token = generation
        editError = nil
        do {
            try await driver.insert(database: database, table: table.name, values: values)
            guard token == generation else { return }
            await reloadCurrentPage()
        } catch {
            guard token == generation else { return }
            editError = error.localizedDescription
        }
    }

    func deleteRow(_ row: Int) async {
        guard let key = keyForRow(row) else {
            editError = "Can't identify this row to delete (no primary key)."
            return
        }
        guard let driver, let database = selectedDatabase, let table = selectedTable else { return }
        let token = generation
        editError = nil
        do {
            try await driver.delete(database: database, table: table.name, key: key)
            guard token == generation else { return }
            await reloadCurrentPage()
        } catch {
            guard token == generation else { return }
            editError = error.localizedDescription
        }
    }

    private func keyForRow(_ rowIndex: Int) -> [ColumnValue]? {
        guard let result = rows, rowIndex >= 0, rowIndex < result.rows.count else { return nil }
        let columnNames = result.columns.map(\.name)
        var key: [ColumnValue] = []
        for pk in columns.primaryKeyColumns {
            guard let idx = columnNames.firstIndex(of: pk.name) else { return nil }
            key.append(ColumnValue(column: pk.name, value: result.rows[rowIndex][idx]))
        }
        return key.isEmpty ? nil : key
    }

    private func inlineCell(for raw: String, column: ColumnInfo) -> Cell {
        if raw.isEmpty, column.isNullable { return .null }
        let type = column.dataType.lowercased()
        if type.contains("int") { return Int64(raw).map(Cell.int) ?? .text(raw) }
        if type.contains("float") || type.contains("double") || type.contains("real") {
            return Double(raw).map(Cell.double) ?? .text(raw)
        }
        return .text(raw)
    }

    private func reloadCurrentPage() async {
        await reloadLoaded()
    }
}
