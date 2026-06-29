import Foundation

public extension DatabaseViewModel {
    func insertRow(_ values: [ColumnValue]) async {
        await performWrite { driver, database, table in
            try await driver.insert(database: database, table: table, values: values)
        }
    }

    func updateRow(at rowIndex: Int, values: [ColumnValue]) async {
        guard let key = keyForRow(rowIndex) else {
            editError = "Can't identify this row to update (no usable primary key)."
            return
        }
        await performWrite { driver, database, table in
            try await driver.update(database: database, table: table, values: values, key: key)
        }
    }

    func deleteRow(at rowIndex: Int) async {
        guard let key = keyForRow(rowIndex) else {
            editError = "Can't identify this row to delete (no usable primary key)."
            return
        }
        await performWrite { driver, database, table in
            try await driver.delete(database: database, table: table, key: key)
        }
    }

    func updateCell(rowIndex: Int, column: String, stringValue: String) async {
        guard let info = currentColumns.first(where: { $0.name == column }),
              let result, rowIndex >= 0, rowIndex < result.rows.count,
              let columnIndex = result.columnNames.firstIndex(of: column) else { return }
        let value = Self.inlineCell(for: stringValue, column: info)
        guard value != result.rows[rowIndex][columnIndex] else { return }
        await updateRow(at: rowIndex, values: [ColumnValue(column: column, value: value)])
    }

    static func inlineCell(for raw: String, column: ColumnInfo) -> Cell {
        if raw.isEmpty, column.isNullable { return .null }
        let type = column.dataType.lowercased()
        if type.contains("int") { return Int64(raw).map(Cell.int) ?? .text(raw) }
        if type.contains("float") || type.contains("double") || type.contains("real") {
            return Double(raw).map(Cell.double) ?? .text(raw)
        }
        return .text(raw)
    }

    private func performWrite(
        _ op: (RelationalDriver, String, String) async throws -> Void
    ) async {
        guard canEditRows, let driver, let database = selectedDatabase, let table = selectedTable
        else { return }
        editError = nil
        isBusy = true
        do {
            try await op(driver, database, table.name)
            await reloadAfterWrite()
        } catch {
            editError = Self.asDatabaseError(error).message
            isBusy = false
        }
    }

    private func keyForRow(_ rowIndex: Int) -> [ColumnValue]? {
        guard let result, rowIndex >= 0, rowIndex < result.rows.count else { return nil }
        let names = result.columnNames
        var key: [ColumnValue] = []
        for pk in primaryKeyColumns {
            guard let idx = names.firstIndex(of: pk.name) else { return nil }
            key.append(ColumnValue(column: pk.name, value: result.rows[rowIndex][idx]))
        }
        return key.isEmpty ? nil : key
    }
}
