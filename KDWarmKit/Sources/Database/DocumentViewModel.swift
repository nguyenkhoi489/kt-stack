import Foundation
import Combine

@MainActor
public final class DocumentViewModel: ObservableObject {

    public enum Connection: Equatable {
        case idle
        case connecting
        case connected
        case failed(DatabaseError)
    }

    @Published public private(set) var connection: Connection = .idle
    @Published public private(set) var selectedProfile: ConnectionProfile?
    @Published public internal(set) var databases: [DatabaseInfo] = []
    @Published public private(set) var selectedDatabase: String?
    @Published public internal(set) var collections: [CollectionInfo] = []
    @Published public private(set) var selectedCollection: String?
    @Published public internal(set) var documents: [DocumentRecord] = []
    @Published public private(set) var resultError: String?
    @Published public internal(set) var isBusy = false
    @Published public private(set) var pageOffset = 0
    @Published public private(set) var hasMorePages = false
    @Published public internal(set) var editError: String?
    @Published public internal(set) var backupStatus: DatabaseViewModel.BackupStatus = .idle
    @Published public var filterText = ""

    public var pageSize = 50

    public var isReadOnlyConnection: Bool { selectedProfile?.readOnly ?? false }

    public typealias DriverFactory = @Sendable (ConnectionProfile, String?) -> DocumentDriver?

    private let makeDriver: DriverFactory
    let passwordFor: @Sendable (ConnectionProfile) -> String?
    private(set) var driver: DocumentDriver?
    private var generation = 0

    public init(makeDriver: @escaping DriverFactory = DocumentViewModel.defaultDriver,
                passwordFor: @escaping @Sendable (ConnectionProfile) -> String? = DocumentViewModel.defaultPassword) {
        self.makeDriver = makeDriver
        self.passwordFor = passwordFor
    }

    public func deselect() {
        generation += 1
        connection = .idle
        selectedProfile = nil
        driver = nil
        databases = []; collections = []; documents = []
        selectedDatabase = nil; selectedCollection = nil
        resultError = nil; editError = nil; filterText = ""
        pageOffset = 0; hasMorePages = false; isBusy = false
    }

    public func select(profile: ConnectionProfile) async {
        let token = beginOperation()
        selectedProfile = profile
        databases = []; collections = []; documents = []
        selectedDatabase = nil; selectedCollection = nil
        resultError = nil; editError = nil; filterText = ""
        pageOffset = 0; hasMorePages = false
        connection = .connecting

        guard let driver = makeDriver(profile, passwordFor(profile)) else {
            connection = .failed(.connection("Unsupported engine: \(profile.kind.rawValue)"))
            isBusy = false
            return
        }
        self.driver = driver
        do {
            try await driver.ping()
            let loaded = try await driver.listDatabases()
            guard token == generation else { return }
            databases = loaded
            connection = .connected
        } catch {
            guard token == generation else { return }
            connection = .failed(Self.asDatabaseError(error))
        }
        if token == generation { isBusy = false }
    }

    public func select(database: String) async {
        guard let driver else { return }
        let token = beginOperation()
        selectedDatabase = database
        collections = []; documents = []; selectedCollection = nil; resultError = nil; editError = nil
        do {
            let loaded = try await driver.listCollections(database: database)
            guard token == generation else { return }
            collections = loaded
        } catch {
            guard token == generation else { return }
            resultError = Self.asDatabaseError(error).message
        }
        if token == generation { isBusy = false }
    }

    public func select(collection: String) async {
        selectedCollection = collection
        pageOffset = 0
        editError = nil
        await loadPage()
    }

    public func applyFilter() async {
        pageOffset = 0
        await loadPage()
    }

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
        guard let driver, let database = selectedDatabase, let collection = selectedCollection else { return }
        let token = beginOperation()
        let filter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let page = try await driver.find(
                database: database, collection: collection,
                filterJSON: filter.isEmpty ? nil : filter,
                limit: pageSize, skip: pageOffset)
            guard token == generation else { return }
            documents = page
            resultError = nil
            hasMorePages = page.count == pageSize
        } catch {
            guard token == generation else { return }
            documents = []
            resultError = Self.asDatabaseError(error).message
        }
        if token == generation { isBusy = false }
    }

    private func beginOperation() -> Int {
        generation += 1
        isBusy = true
        return generation
    }

    static func asDatabaseError(_ error: Error) -> DatabaseError {
        (error as? DatabaseError) ?? .connection(error.localizedDescription)
    }
}
