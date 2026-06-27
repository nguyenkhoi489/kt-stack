import Foundation
import Combine

@MainActor
public final class DatabaseV2ViewModel: ObservableObject {

    public enum ConnectionState {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var databases: [DatabaseInfo] = []
    @Published public private(set) var tables: [TableInfo] = []
    @Published public private(set) var selectedDatabase: String?
    @Published public private(set) var selectedTable: TableInfo?

    @Published public private(set) var rows: QueryResult?
    @Published public private(set) var pageOffset: Int = 0
    @Published public private(set) var hasMore: Bool = false
    @Published public private(set) var isLoadingRows: Bool = false
    @Published public private(set) var isLoadingStructure: Bool = false

    @Published public private(set) var columns: [ColumnInfo] = []
    @Published public private(set) var indexes: [IndexInfo] = []
    @Published public private(set) var foreignKeys: [ForeignKeyRelation] = []
    @Published public private(set) var diagramColumns: [String: [ColumnInfo]] = [:]
    @Published public private(set) var isLoadingDiagram: Bool = false
    @Published public private(set) var diagramLoaded: Bool = false

    @Published public private(set) var loadError: String?
    @Published public internal(set) var editError: String?
    @Published public internal(set) var ddlError: String?
    @Published public internal(set) var isDDLBusy: Bool = false

    @Published public var queryTabs: [V2QueryTab]
    @Published public internal(set) var activeQueryTabID: UUID?
    public private(set) var connectionProfileID: String?
    @Published public private(set) var connectionKind: DatabaseKind?

    public var schemaName: String { selectedDatabase ?? "" }
    public let pageSize: Int = 200

    public var schemaCatalog: SchemaCatalog {
        SchemaCatalog(
            tables: tables.map(\.name),
            columnsByTable: diagramColumns.mapValues { $0.map(\.name) },
            detailedColumnsByTable: diagramColumns,
            relations: foreignKeys
        )
    }

    private let makeDriver: DatabaseViewModel.DriverFactory
    private let passwordFor: @Sendable (ConnectionProfile) -> String?
    var driver: RelationalDriver?
    var generation = 0

    public init(
        makeDriver: @escaping DatabaseViewModel.DriverFactory = DatabaseViewModel.defaultDriver,
        passwordFor: @escaping @Sendable (ConnectionProfile) -> String? = DatabaseViewModel.defaultPassword
    ) {
        self.makeDriver = makeDriver
        self.passwordFor = passwordFor
        let initialTab = V2QueryTab(title: "Query 1")
        self.queryTabs = [initialTab]
        self.activeQueryTabID = initialTab.id
    }

    public func connect(profile: ConnectionProfile) async {
        generation += 1
        let token = generation
        let previousDriver = driver
        driver = nil
        connectionState = .connecting
        connectionProfileID = profile.id.uuidString
        connectionKind = profile.kind
        databases = []
        tables = []
        selectedDatabase = nil
        selectedTable = nil
        resetTableState()
        foreignKeys = []
        diagramColumns = [:]
        diagramLoaded = false
        await previousDriver?.closeSession()

        guard token == generation else { return }

        guard let newDriver = makeDriver(profile, passwordFor(profile)) else {
            connectionState = .failed("Unsupported engine: \(profile.kind.rawValue)")
            return
        }
        driver = newDriver
        do {
            try await newDriver.ping()
            let dbs = try await newDriver.listDatabases()
            guard token == generation else { return }
            try? await newDriver.openSession()
            databases = dbs
            connectionState = .connected
            if let firstDatabase = dbs.first {
                await select(database: firstDatabase.name)
            }
        } catch {
            guard token == generation else { return }
            connectionState = .failed(error.localizedDescription)
            driver = nil
        }
    }

    public func disconnect() async {
        generation += 1
        let oldDriver = driver
        driver = nil
        connectionState = .idle
        databases = []
        tables = []
        selectedDatabase = nil
        selectedTable = nil
        resetTableState()
        foreignKeys = []
        diagramColumns = [:]
        diagramLoaded = false
        await oldDriver?.closeSession()
    }

    public func select(database: String) async {
        guard let driver else { return }
        generation += 1
        let token = generation
        selectedDatabase = database
        tables = []
        selectedTable = nil
        resetTableState()
        foreignKeys = []
        diagramColumns = [:]
        diagramLoaded = false
        loadError = nil
        do {
            let result = try await driver.listTables(database: database)
            guard token == generation else { return }
            tables = result
        } catch {
            guard token == generation else { return }
            loadError = error.localizedDescription
        }
    }

    public func select(table: TableInfo) {
        generation += 1
        let token = generation
        selectedTable = table
        resetTableState()
        isLoadingRows = true
        isLoadingStructure = true
        Task {
            await loadRows(table: table, token: token)
            await loadStructure(table: table, token: token)
        }
    }

    public func loadRows(table: TableInfo, token: Int? = nil) async {
        let token = token ?? generation
        guard let driver, let database = selectedDatabase else {
            isLoadingRows = false
            return
        }
        isLoadingRows = true
        loadError = nil
        do {
            let result = try await driver.paginatedRows(
                database: database, table: table.name, limit: pageSize, offset: 0
            )
            guard token == generation else { return }
            rows = result
            pageOffset = result.rowCount
            hasMore = result.rowCount == pageSize
        } catch {
            guard token == generation else { return }
            loadError = error.localizedDescription
        }
        isLoadingRows = false
    }

    public func fetchMore() async {
        let token = generation
        guard let driver, let database = selectedDatabase, let table = selectedTable,
              hasMore, !isLoadingRows else { return }
        isLoadingRows = true
        do {
            let result = try await driver.paginatedRows(
                database: database, table: table.name, limit: pageSize, offset: pageOffset
            )
            guard token == generation else { return }
            if let existing = rows {
                rows = QueryResult(
                    columns: existing.columns,
                    rows: existing.rows + result.rows,
                    truncated: result.truncated,
                    estimatedTotal: result.estimatedTotal
                )
            } else {
                rows = result
            }
            pageOffset += result.rowCount
            hasMore = result.rowCount == pageSize
        } catch {
            guard token == generation else { return }
            loadError = error.localizedDescription
        }
        isLoadingRows = false
    }

    func reloadLoaded() async {
        let token = generation
        guard let driver, let database = selectedDatabase, let table = selectedTable else { return }
        let limit = max(pageOffset, pageSize)
        do {
            let result = try await driver.paginatedRows(
                database: database, table: table.name, limit: limit, offset: 0
            )
            guard token == generation else { return }
            rows = result
            pageOffset = result.rowCount
            hasMore = result.rowCount == limit
        } catch {
            guard token == generation else { return }
            loadError = error.localizedDescription
        }
    }

    public func loadStructure(table: TableInfo, token: Int? = nil) async {
        let token = token ?? generation
        guard let driver, let database = selectedDatabase else {
            isLoadingStructure = false
            return
        }
        do {
            let cols = try await driver.columns(database: database, table: table.name)
            guard token == generation else { return }
            let idxs = try await driver.indexes(database: database, table: table.name)
            guard token == generation else { return }
            let fks = try await driver.foreignKeys(database: database)
            guard token == generation else { return }
            columns = cols
            indexes = idxs
            foreignKeys = fks
        } catch {
            guard token == generation else { return }
            loadError = error.localizedDescription
        }
        isLoadingStructure = false
    }

    public func loadDiagram() async {
        guard !diagramLoaded else { return }
        let token = generation
        guard let driver, let database = selectedDatabase else { return }
        isLoadingDiagram = true
        loadError = nil
        do {
            let cols = try await driver.allColumnsDetailed(database: database)
            guard token == generation else { isLoadingDiagram = false; return }
            let fks = try await driver.foreignKeys(database: database)
            guard token == generation else { isLoadingDiagram = false; return }
            diagramColumns = cols
            foreignKeys = fks
            diagramLoaded = true
        } catch {
            guard token == generation else { isLoadingDiagram = false; return }
            loadError = error.localizedDescription
        }
        isLoadingDiagram = false
    }

    private func resetTableState() {
        rows = nil
        pageOffset = 0
        hasMore = false
        isLoadingRows = false
        isLoadingStructure = false
        columns = []
        indexes = []
        loadError = nil
        editError = nil
        ddlError = nil
    }

    func reloadAfterDDL() async {
        if let database = selectedDatabase {
            tables = (try? await driver?.listTables(database: database)) ?? tables
        }
        if let table = selectedTable {
            await loadStructure(table: table)
        }
    }
}
