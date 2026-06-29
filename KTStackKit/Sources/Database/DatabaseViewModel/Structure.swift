import Foundation

public extension DatabaseViewModel {
    private var ddlDialect: SQLDialect {
        SQLDialect.forKind(selectedProfile?.kind ?? .mysql)
    }

    var canDropDatabase: Bool {
        selectedProfile?.kind == .mysql || selectedProfile?.kind == .postgres
    }

    func loadStructure() async {
        guard let driver, let database = selectedDatabase, let table = selectedTable else {
            currentIndexes = []
            return
        }
        if currentColumns.isEmpty {
            currentColumns = await (try? driver.columns(database: database, table: table.name)) ?? []
        }
        currentIndexes = await (try? driver.indexes(database: database, table: table.name)) ?? []
    }

    func prepareCreateTable(name: String, columns: [ColumnDefinition]) {
        stageDDL { try ddlDialect.createTable(schema: requireDatabase(), table: name, columns: columns) }
    }

    func prepareAddColumn(_ column: ColumnDefinition) {
        stageDDL {
            let (db, table) = try requireTable()
            return try ddlDialect.addColumn(schema: db, table: table, column: column)
        }
    }

    func prepareDropColumn(_ column: String) {
        stageDDL {
            let (db, table) = try requireTable()
            return try ddlDialect.dropColumn(schema: db, table: table, column: column)
        }
    }

    func prepareDropDatabase(_ name: String) {
        stageDDL { try ddlDialect.dropDatabase(name) }
    }

    @discardableResult
    func confirmDropDatabase(_ name: String) async -> Bool {
        guard let sql = pendingDDL else { return false }
        pendingDDL = nil
        guard !isReadOnlyConnection else {
            ddlError = "This connection is read-only."
            return false
        }
        guard await runConfirmedDDL(sql, database: nil) else { return false }
        if let refreshed = try? await driver?.listDatabases() {
            databases = refreshed
        }
        if selectedDatabase == name { clearSelectedDatabase() }
        return true
    }

    func prepareDropTable() {
        stageDDL {
            let (db, table) = try requireTable()
            return try ddlDialect.dropTable(schema: db, table: table)
        }
    }

    func cancelDDL() {
        pendingDDL = nil
    }

    func clearDDLError() {
        ddlError = nil
    }

    func confirmDDL() async {
        guard let sql = pendingDDL else { return }
        pendingDDL = nil
        guard !isReadOnlyConnection else {
            ddlError = "This connection is read-only."
            return
        }
        guard await runConfirmedDDL(sql, database: selectedDatabase) else { return }
        if let database = selectedDatabase {
            tables = await (try? driver?.listTables(database: database)) ?? tables
        }
        await loadStructure()
    }

    private func stageDDL(_ build: () throws -> String) {
        do {
            ddlError = nil
            pendingDDL = try build()
        } catch {
            pendingDDL = nil
            ddlError = Self.asDatabaseError(error).message
        }
    }

    private func runConfirmedDDL(_ sql: String, database: String?) async -> Bool {
        guard let driver else { return false }
        isBusy = true
        ddlError = nil
        defer { isBusy = false }
        do {
            _ = try await driver.query(sql, database: database)
            recordQueryHistory(sql)
            return true
        } catch {
            recordQueryHistory(sql)
            ddlError = Self.asDatabaseError(error).message
            return false
        }
    }

    private func requireDatabase() throws -> String {
        guard let database = selectedDatabase else {
            throw DatabaseError.connection("Pick a database first.")
        }
        return database
    }

    private func requireTable() throws -> (database: String, table: String) {
        guard let database = selectedDatabase, let table = selectedTable else {
            throw DatabaseError.connection("Pick a table first.")
        }
        return (database, table.name)
    }
}
