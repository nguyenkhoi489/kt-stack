import Foundation

public extension DatabaseV2ViewModel {
    private var ddlDialect: SQLDialect {
        SQLDialect.forKind(driver?.kind ?? .mysql)
    }

    func composeCreateTable(name: String, columns: [ColumnDefinition]) -> String {
        guard let database = selectedDatabase else {
            ddlError = "Select a database first."
            return ""
        }
        do {
            ddlError = nil
            return try ddlDialect.createTable(schema: database, table: name, columns: columns)
        } catch {
            ddlError = error.localizedDescription
            return ""
        }
    }

    func composeAddColumn(_ column: ColumnDefinition) -> String {
        guard let database = selectedDatabase, let table = selectedTable else {
            ddlError = "Select a table first."
            return ""
        }
        do {
            ddlError = nil
            return try ddlDialect.addColumn(schema: database, table: table.name, column: column)
        } catch {
            ddlError = error.localizedDescription
            return ""
        }
    }

    func composeDropColumn(_ column: String) -> String {
        guard let database = selectedDatabase, let table = selectedTable else {
            ddlError = "Select a table first."
            return ""
        }
        do {
            ddlError = nil
            return try ddlDialect.dropColumn(schema: database, table: table.name, column: column)
        } catch {
            ddlError = error.localizedDescription
            return ""
        }
    }

    func composeDropTable() -> String {
        guard let database = selectedDatabase, let table = selectedTable else {
            ddlError = "Select a table first."
            return ""
        }
        do {
            ddlError = nil
            return try ddlDialect.dropTable(schema: database, table: table.name)
        } catch {
            ddlError = error.localizedDescription
            return ""
        }
    }

    func runDDL(_ sql: String) async {
        guard !sql.isEmpty, let driver else { return }
        let token = generation
        isDDLBusy = true
        ddlError = nil
        defer { isDDLBusy = false }
        do {
            _ = try await driver.query(sql, database: selectedDatabase)
            guard token == generation else { return }
            await reloadAfterDDL()
        } catch {
            guard token == generation else { return }
            ddlError = error.localizedDescription
        }
    }

    func clearDDLError() {
        ddlError = nil
    }
}
