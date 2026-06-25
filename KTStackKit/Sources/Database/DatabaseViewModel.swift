import Foundation
import Combine

@MainActor
public final class DatabaseViewModel: ObservableObject {

    public enum Connection: Equatable {
        case idle
        case connecting
        case connected
        case failed(DatabaseError)
    }

    public enum ResultSource: Equatable {
        case none
        case table(database: String, table: String)
        case query
    }

    @Published public private(set) var connection: Connection = .idle
    @Published public private(set) var selectedProfile: ConnectionProfile?
    @Published public internal(set) var databases: [DatabaseInfo] = []
    @Published public private(set) var selectedDatabase: String?
    @Published public internal(set) var tables: [TableInfo] = []
    @Published public private(set) var selectedTable: TableInfo?
    @Published public internal(set) var result: QueryResult?
    @Published public internal(set) var resultError: String?
    @Published public internal(set) var resultNotice: String?
    @Published public internal(set) var resultSource: ResultSource = .none
    @Published public internal(set) var queryTabs: [QueryTab] = [QueryTab(title: "Query 1")]
    @Published public internal(set) var activeQueryTabID: UUID?
    @Published public internal(set) var queryHistoryEntries: [QueryHistoryEntry] = []
 
    @Published public internal(set) var isBusy = false
    @Published public private(set) var pageOffset = 0

    @Published public internal(set) var hasMorePages = false

    @Published public internal(set) var isFetchingMore = false

    @Published public internal(set) var currentActivityLabel: String?

    @Published public internal(set) var activeFilters: [FilterCondition] = []
    @Published public internal(set) var activeSort: SortSpec?
    @Published public internal(set) var navigationStack: [BreadcrumbEntry] = []

    private var isIncrementalBrowse = false
    private var schemaColumnsLoaded = false
    private var schemaDetailedLoaded = false

    private var browseDialect: SQLDialect { SQLDialect.forKind(selectedProfile?.kind ?? .mysql) }

    @Published public internal(set) var currentColumns: [ColumnInfo] = []

    @Published public internal(set) var currentIndexes: [IndexInfo] = []

    @Published public private(set) var schemaCatalog: SchemaCatalog = .empty

    @Published public internal(set) var pendingDangerousSQL: String?

    /// Composed DDL awaiting user confirmation. The UI shows it verbatim; nothing runs until confirmed.
    @Published public internal(set) var pendingDDL: String?

    @Published public internal(set) var ddlError: String?

    @Published public internal(set) var dumpStatus: DumpStatus = .idle

    @Published public internal(set) var backupStatus: BackupStatus = .idle

    @Published public internal(set) var editError: String?

  
    public var pageSize = 100


    public var isTableBrowse: Bool {
        if case .table = resultSource { return true }
        return false
    }

    public var primaryKeyColumns: [ColumnInfo] { currentColumns.primaryKeyColumns }

    public var isReadOnlyConnection: Bool { selectedProfile?.readOnly ?? false }


    public var editDisabledReason: String? {
        if isReadOnlyConnection { return "This connection is read-only." }
        guard isTableBrowse else { return "Editing is only available when browsing a single table." }
        guard !primaryKeyColumns.isEmpty else {
            return "This table has no primary key, so rows can't be edited safely."
        }
        return nil
    }

   
    public var canEditRows: Bool { editDisabledReason == nil }

    public typealias DriverFactory = @Sendable (ConnectionProfile, String?) -> RelationalDriver?

    /// Terminal state of a dump (export/import) operation, surfaced to the import/export sheet.
    public enum DumpStatus: Equatable {
        case idle
        case running
        case done(String)
        case failed(String)
    }

    private let makeDriver: DriverFactory
    let passwordFor: @Sendable (ConnectionProfile) -> String?
    let dumpService: DumpService
    let historyStore: QueryHistoryStore

    private(set) var driver: RelationalDriver?


    private var generation = 0
    var queryGenerations: [UUID: Int] = [:]

    public init(makeDriver: @escaping DriverFactory = DatabaseViewModel.defaultDriver,
                passwordFor: @escaping @Sendable (ConnectionProfile) -> String? = DatabaseViewModel.defaultPassword,
                dumpService: DumpService = DumpService(),
                historyStore: QueryHistoryStore = QueryHistoryStore()) {
        self.makeDriver = makeDriver
        self.passwordFor = passwordFor
        self.dumpService = dumpService
        self.historyStore = historyStore
        self.queryHistoryEntries = historyStore.entries()
        self.activeQueryTabID = queryTabs.first?.id
    }

    // MARK: - Connection


    public func deselect() {
        let previousDriver = driver
        generation += 1
        connection = .idle
        selectedProfile = nil
        driver = nil
        databases = []; tables = []; selectedDatabase = nil; selectedTable = nil
        result = nil; resultError = nil; resultNotice = nil; resultSource = .none
        resetQueryWorkspace()
        currentColumns = []; currentIndexes = []
        schemaCatalog = .empty
        pageOffset = 0; hasMorePages = false; isBusy = false; isFetchingMore = false
        isIncrementalBrowse = false; schemaColumnsLoaded = false; schemaDetailedLoaded = false; currentActivityLabel = nil
        activeFilters = []; activeSort = nil; navigationStack = []
        if let previousDriver { Task { await previousDriver.closeSession() } }
    }

    func clearSelectedDatabase() {
        selectedDatabase = nil
        tables = []; selectedTable = nil
        result = nil; resultError = nil; resultNotice = nil; resultSource = .none
        clearQueryTabResults()
        currentColumns = []; currentIndexes = []
        schemaCatalog = .empty
        schemaColumnsLoaded = false
        schemaDetailedLoaded = false
    }

    public func select(profile: ConnectionProfile) async {
        let previousDriver = driver
        let token = beginOperation()
        selectedProfile = profile
        databases = []; tables = []; selectedDatabase = nil; selectedTable = nil
        result = nil; resultError = nil; resultNotice = nil; resultSource = .none; pageOffset = 0; hasMorePages = false
        clearQueryTabResults()
        schemaCatalog = .empty; schemaColumnsLoaded = false; schemaDetailedLoaded = false
        connection = .connecting
        currentActivityLabel = "Connecting…"
        await previousDriver?.closeSession()

        guard let driver = makeDriver(profile, passwordFor(profile)) else {
            connection = .failed(.connection("Unsupported engine: \(profile.kind.rawValue)"))
            isBusy = false; currentActivityLabel = nil
            return
        }
        self.driver = driver
        do {
            try await driver.ping()
            let dbs = try await driver.listDatabases()
            guard token == generation else { return }
            try? await driver.openSession()
            databases = dbs
            connection = .connected
        } catch {
            guard token == generation else { return }
            connection = .failed(Self.asDatabaseError(error))
        }
        if token == generation { isBusy = false; currentActivityLabel = nil }
    }

    // MARK: - Schema

    public func select(database: String) async {
        guard prepareDatabaseSelection(database) else { return }
        await loadTables(of: database)
    }

    public func selectDatabaseDeferred(_ database: String) {
        guard prepareDatabaseSelection(database) else { return }
        Task { await loadTables(of: database) }
    }

    @discardableResult
    private func prepareDatabaseSelection(_ database: String) -> Bool {
        guard driver != nil else { return false }
        _ = beginOperation()
        selectedDatabase = database
        tables = []; selectedTable = nil; result = nil; resultError = nil; resultSource = .none
        clearQueryTabResults()
        schemaCatalog = .empty; schemaColumnsLoaded = false; schemaDetailedLoaded = false
        activeFilters = []; activeSort = nil; navigationStack = []
        return true
    }

    private func loadTables(of database: String) async {
        guard let driver else { return }
        let token = generation
        currentActivityLabel = "Loading tables…"
        do {
            let loaded = try await driver.listTables(database: database)
            guard token == generation else { return }
            tables = loaded
            schemaCatalog = SchemaCatalog(tables: loaded.map(\.name))
        } catch {
            guard token == generation else { return }
            resultError = Self.asDatabaseError(error).message
        }
        if token == generation { isBusy = false; currentActivityLabel = nil }
    }

    public func ensureSchemaCatalogLoaded() async {
        guard let driver, let database = selectedDatabase, !schemaColumnsLoaded else { return }
        let token = generation
        schemaColumnsLoaded = true
        do {
            let map = try await driver.allColumns(database: database)
            guard token == generation else { schemaColumnsLoaded = false; return }
            schemaCatalog = SchemaCatalog(tables: schemaCatalog.tables,
                                          columnsByTable: map,
                                          detailedColumnsByTable: schemaCatalog.detailedColumnsByTable,
                                          relations: schemaCatalog.relations)
        } catch {
            schemaColumnsLoaded = false
        }
    }

    public func ensureDetailedColumnsLoaded() async {
        guard let driver, let database = selectedDatabase, !schemaDetailedLoaded else { return }
        let token = generation
        schemaDetailedLoaded = true
        do {
            let detailed = try await driver.allColumnsDetailed(database: database)
            guard token == generation else { schemaDetailedLoaded = false; return }
            schemaCatalog = schemaCatalog.withDetailedColumns(detailed)
        } catch {
            schemaDetailedLoaded = false
        }
    }

    public func loadRelationsIfNeeded() async {
        guard let driver, let database = selectedDatabase else { return }
        guard schemaCatalog.relations.isEmpty else { return }
        let token = generation
        let relations = (try? await driver.foreignKeys(database: database)) ?? []
        guard token == generation else { return }
        schemaCatalog = schemaCatalog.withRelations(relations)
    }

    public func select(table: TableInfo) async {
        navigationStack = []
        await loadSelectedTable(table, filters: [], sort: nil)
    }

    func loadSelectedTable(_ table: TableInfo,
                           filters: [FilterCondition], sort: SortSpec?) async {
        guard let driver, let database = selectedDatabase else { return }
        selectedTable = table
        pageOffset = 0
        isIncrementalBrowse = false
        activeFilters = []; activeSort = nil
        currentColumns = []
        currentIndexes = []
        let token = beginOperation()

        do {
            let cols = try await driver.columns(database: database, table: table.name)
            guard token == generation else { return }
            currentColumns = cols
        } catch {
            guard token == generation else { return }
            currentColumns = []
        }
        activeFilters = filters.filter { columnIsBrowsable($0.column) }
        activeSort = sort.flatMap { columnIsBrowsable($0.column) ? $0 : nil }
        await loadPage()
    }

    // MARK: - Filter + sort

    public func applyFilters(_ filters: [FilterCondition]) async {
        activeFilters = filters.filter { columnIsBrowsable($0.column) }
        pageOffset = 0; isIncrementalBrowse = false
        await loadPage()
    }

    public func applySort(_ sort: SortSpec?) async {
        if let sort, !columnIsBrowsable(sort.column) { return }
        activeSort = sort
        pageOffset = 0; isIncrementalBrowse = false
        await loadPage()
    }

    public func toggleSort(column: String) async {
        guard columnIsBrowsable(column) else { return }
        let next: SortSpec?
        if activeSort?.column == column {
            next = activeSort?.ascending == true ? SortSpec(column: column, ascending: false) : nil
        } else {
            next = SortSpec(column: column, ascending: true)
        }
        await applySort(next)
    }

    public func clearFiltersAndSort() async {
        guard !activeFilters.isEmpty || activeSort != nil else { return }
        activeFilters = []; activeSort = nil
        pageOffset = 0; isIncrementalBrowse = false
        await loadPage()
    }

    private func columnIsBrowsable(_ name: String) -> Bool {
        currentColumns.contains { $0.name == name }
    }

    private func fetchBrowsePage(database: String, table: String,
                                 limit: Int, offset: Int) async throws -> QueryResult {
        guard let driver else { throw DatabaseError.connection("No active connection") }
        if activeFilters.isEmpty, activeSort == nil {
            return try await driver.paginatedRows(database: database, table: table,
                                                  limit: limit, offset: offset)
        }
        let statement = try browseDialect.browseSelect(
            schema: database, table: table,
            filters: activeFilters, sort: activeSort, limit: limit, offset: offset)
        return try await driver.runSelect(statement, database: database)
    }

    // MARK: - Pagination

    public func nextPage() async {
        guard hasMorePages else { return }
        isIncrementalBrowse = false
        pageOffset += pageSize
        await loadPage()
    }

    public func previousPage() async {
        guard pageOffset > 0 else { return }
        isIncrementalBrowse = false
        pageOffset = max(0, pageOffset - pageSize)
        await loadPage()
    }

    public func loadMoreRows() async {
        guard hasMorePages, !isFetchingMore,
              let driver, let database = selectedDatabase, let table = selectedTable,
              let current = result, case .table = resultSource else { return }
        let token = generation
        let expectedColumns = current.columns
        let nextOffset = pageOffset + pageSize
        isFetchingMore = true
        currentActivityLabel = "Loading more…"
        defer { isFetchingMore = false; currentActivityLabel = nil }
        do {
            let page = try await fetchBrowsePage(
                database: database, table: table.name, limit: pageSize + 1, offset: nextOffset)
            guard token == generation, let latest = result, latest.columns == expectedColumns else { return }
            if page.rows.isEmpty {
                hasMorePages = false
                return
            }
            guard page.columns == expectedColumns else { return }
            let hasMore = page.rowCount > pageSize
            let appended = hasMore ? Array(page.rows.prefix(pageSize)) : page.rows
            result = QueryResult(columns: latest.columns, rows: latest.rows + appended)
            pageOffset = nextOffset
            hasMorePages = hasMore
            isIncrementalBrowse = true
        } catch {
            return
        }
    }

    func reloadAfterWrite() async {
        if isIncrementalBrowse {
            await reloadLoadedRows()
        } else {
            await loadPage()
        }
    }

    private func reloadLoadedRows() async {
        guard let driver, let database = selectedDatabase, let table = selectedTable,
              let current = result else { return }
        let loadedCount = current.rowCount
        let token = beginOperation()
        do {
            let page = try await fetchBrowsePage(
                database: database, table: table.name, limit: loadedCount + 1, offset: 0)
            guard token == generation else { return }
            let hasMore = page.rowCount > loadedCount
            result = hasMore
                ? QueryResult(columns: page.columns, rows: Array(page.rows.prefix(loadedCount)))
                : page
            resultError = nil
            resultSource = .table(database: database, table: table.name)
            hasMorePages = hasMore
            pageOffset = max(0, (result?.rowCount ?? 0) - pageSize)
            isIncrementalBrowse = true
        } catch {
            guard token == generation else { return }
            resultError = Self.asDatabaseError(error).message
        }
        if token == generation { isBusy = false }
    }

    func loadPage() async {
        guard let driver, let database = selectedDatabase, let table = selectedTable else { return }
        let token = beginOperation()
        currentActivityLabel = "Loading rows…"
        do {
            let page = try await fetchBrowsePage(
                database: database, table: table.name, limit: pageSize + 1, offset: pageOffset)
            guard token == generation else { return }
            let hasMore = page.rowCount > pageSize
            result = hasMore
                ? QueryResult(columns: page.columns, rows: Array(page.rows.prefix(pageSize)))
                : page
            resultError = nil
            resultSource = .table(database: database, table: table.name)
            hasMorePages = hasMore
        } catch {
            guard token == generation else { return }
            result = nil
            resultError = Self.asDatabaseError(error).message
            resultSource = .none
        }
        if token == generation { isBusy = false; currentActivityLabel = nil }
    }

    public func clearEditError() { editError = nil }

    // MARK: - Helpers

    private func beginOperation() -> Int {
        generation += 1
        isBusy = true
        isFetchingMore = false
        currentActivityLabel = nil
        return generation
    }

    static func asDatabaseError(_ error: Error) -> DatabaseError {
        (error as? DatabaseError) ?? .connection(error.localizedDescription)
    }
}
