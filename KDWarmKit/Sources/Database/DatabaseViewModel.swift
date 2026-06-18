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
    @Published public internal(set) var resultSource: ResultSource = .none
    @Published public internal(set) var queryTabs: [QueryTab] = [QueryTab(title: "Query 1")]
    @Published public internal(set) var activeQueryTabID: UUID?
    @Published public internal(set) var queryHistoryEntries: [QueryHistoryEntry] = []
 
    @Published public internal(set) var isBusy = false
    @Published public private(set) var pageOffset = 0
    
    @Published public internal(set) var hasMorePages = false

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
        generation += 1
        connection = .idle
        selectedProfile = nil
        driver = nil
        databases = []; tables = []; selectedDatabase = nil; selectedTable = nil
        result = nil; resultError = nil; resultSource = .none
        resetQueryWorkspace()
        currentColumns = []; currentIndexes = []
        schemaCatalog = .empty
        pageOffset = 0; hasMorePages = false; isBusy = false
    }

    func clearSelectedDatabase() {
        selectedDatabase = nil
        tables = []; selectedTable = nil
        result = nil; resultError = nil; resultSource = .none
        clearQueryTabResults()
        currentColumns = []; currentIndexes = []
        schemaCatalog = .empty
    }

    public func select(profile: ConnectionProfile) async {
        let token = beginOperation()
        selectedProfile = profile
        databases = []; tables = []; selectedDatabase = nil; selectedTable = nil
        result = nil; resultError = nil; resultSource = .none; pageOffset = 0; hasMorePages = false
        clearQueryTabResults()
        schemaCatalog = .empty
        connection = .connecting

        guard let driver = makeDriver(profile, passwordFor(profile)) else {
            connection = .failed(.connection("Unsupported engine: \(profile.kind.rawValue)"))
            isBusy = false
            return
        }
        self.driver = driver
        do {
            try await driver.ping()
            let dbs = try await driver.listDatabases()
            guard token == generation else { return }
            databases = dbs
            connection = .connected
        } catch {
            guard token == generation else { return }
            connection = .failed(Self.asDatabaseError(error))
        }
        if token == generation { isBusy = false }
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
        schemaCatalog = .empty
        return true
    }

    private func loadTables(of database: String) async {
        guard let driver else { return }
        let token = generation
        do {
            let loaded = try await driver.listTables(database: database)
            guard token == generation else { return }
            tables = loaded
        } catch {
            guard token == generation else { return }
            resultError = Self.asDatabaseError(error).message
        }
        if token == generation { isBusy = false }
        await buildSchemaCatalog(of: database, token: token)
    }

    private func buildSchemaCatalog(of database: String, token: Int) async {
        guard let driver else { return }
        let tableNames = tables.map(\.name)
        let map = (try? await driver.allColumns(database: database)) ?? [:]
        guard token == generation else { return }
        schemaCatalog = SchemaCatalog(tables: tableNames, columnsByTable: map)
    }

    public func select(table: TableInfo) async {
        guard let driver, let database = selectedDatabase else { return }
        selectedTable = table
        pageOffset = 0
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
        await loadPage()
    }

    // MARK: - Pagination

    public func nextPage() async {
        guard hasMorePages else { return }
        pageOffset += pageSize
        await loadPage()
    }

    public func previousPage() async {
        guard pageOffset > 0 else { return }
        pageOffset = max(0, pageOffset - pageSize)
        await loadPage()
    }

    func loadPage() async {
        guard let driver, let database = selectedDatabase, let table = selectedTable else { return }
        let token = beginOperation()
        do {
            let page = try await driver.paginatedRows(
                database: database, table: table.name, limit: pageSize, offset: pageOffset)
            guard token == generation else { return }
            result = page
            resultError = nil
            resultSource = .table(database: database, table: table.name)
            hasMorePages = page.rowCount == pageSize
        } catch {
            guard token == generation else { return }
            result = nil
            resultError = Self.asDatabaseError(error).message
            resultSource = .none
        }
        if token == generation { isBusy = false }
    }

    public func clearEditError() { editError = nil }

    // MARK: - Helpers

    private func beginOperation() -> Int {
        generation += 1
        isBusy = true
        return generation
    }

    static func asDatabaseError(_ error: Error) -> DatabaseError {
        (error as? DatabaseError) ?? .connection(error.localizedDescription)
    }
}
