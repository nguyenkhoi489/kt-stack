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

    private func performWrite(
        _ op: (RelationalDriver, String, String) async throws -> Void) async {
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
