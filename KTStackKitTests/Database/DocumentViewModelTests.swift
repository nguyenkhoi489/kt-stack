import XCTest
@testable import KTStackKit

@MainActor
final class DocumentViewModelTests: XCTestCase {
    private final class StubDocumentDriver: DocumentDriver, @unchecked Sendable {
        let kind: DatabaseKind = .mongodb
        var pingShouldThrow: DatabaseError?
        var findShouldThrow: DatabaseError?
        var writeShouldThrow: DatabaseError?
        private(set) var findCalls: [(database: String, collection: String, filterJSON: String?, limit: Int, skip: Int)] = []
        private(set) var insertCalls: [String] = []
        private(set) var updateCalls: [(record: DocumentRecord, json: String)] = []
        private(set) var deleteCalls: [DocumentRecord] = []

        func ping() async throws {
            if let pingShouldThrow { throw pingShouldThrow }
        }

        func listDatabases() async throws -> [DatabaseInfo] {
            [DatabaseInfo(name: "shop"), DatabaseInfo(name: "admin")]
        }

        func listCollections(database _: String) async throws -> [CollectionInfo] {
            [CollectionInfo(name: "users"), CollectionInfo(name: "orders")]
        }

        func find(
            database: String,
            collection: String,
            filterJSON: String?,
            limit: Int,
            skip: Int
        ) async throws -> [DocumentRecord] {
            findCalls.append((database, collection, filterJSON, limit, skip))
            if let findShouldThrow { throw findShouldThrow }
            return (0..<limit).map {
                DocumentRecord(id: "\(skip + $0)", json: "{\"_id\":\(skip + $0)}", identifierJSON: "\(skip + $0)")
            }
        }

        func aggregate(
            database _: String,
            collection _: String,
            pipelineJSON _: String,
            limit _: Int
        ) async throws -> [DocumentRecord] {
            []
        }

        func insert(database _: String, collection _: String, json: String) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            insertCalls.append(json)
        }

        func update(
            database _: String,
            collection _: String,
            record: DocumentRecord,
            json: String
        ) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            updateCalls.append((record, json))
        }

        func delete(database _: String, collection _: String, record: DocumentRecord) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            deleteCalls.append(record)
        }

        private(set) var createdCollections: [String] = []
        private(set) var droppedCollections: [String] = []
        func createCollection(database _: String, name: String) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            createdCollections.append(name)
        }

        func dropCollection(database _: String, collection: String) async throws {
            if let writeShouldThrow { throw writeShouldThrow }
            droppedCollections.append(collection)
        }
    }

    private func makeVM(_ driver: StubDocumentDriver) -> DocumentViewModel {
        DocumentViewModel(makeDriver: { _, _ in driver }, passwordFor: { _ in nil })
    }

    private func browseCollection(_ driver: StubDocumentDriver) async -> DocumentViewModel {
        let vm = makeVM(driver)
        vm.pageSize = 5
        await vm.select(profile: .managedMongo)
        await vm.select(database: "shop")
        await vm.select(collection: "users")
        return vm
    }

    func testSelectingConnectionLoadsDatabases() async {
        let vm = makeVM(StubDocumentDriver())
        await vm.select(profile: .managedMongo)
        XCTAssertEqual(vm.connection, .connected)
        XCTAssertEqual(vm.databases.map(\.name), ["shop", "admin"])
        XCTAssertFalse(vm.isBusy)
    }

    func testSelectingDatabaseLoadsCollections() async {
        let vm = makeVM(StubDocumentDriver())
        await vm.select(profile: .managedMongo)
        await vm.select(database: "shop")
        XCTAssertEqual(vm.collections.map(\.name), ["users", "orders"])
    }

    func testSelectingCollectionLoadsFirstPage() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        XCTAssertEqual(vm.documents.count, 5)
        XCTAssertEqual(vm.pageOffset, 0)
        XCTAssertTrue(vm.hasMorePages)
        XCTAssertEqual(driver.findCalls.last?.filterJSON, nil)
    }

    func testFilterAppliesToFind() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        vm.filterText = #"{"active":true}"#
        await vm.applyFilter()
        XCTAssertEqual(driver.findCalls.last?.filterJSON, #"{"active":true}"#)
        XCTAssertEqual(vm.pageOffset, 0)
    }

    func testPaginationAdvancesSkip() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        await vm.nextPage()
        XCTAssertEqual(vm.pageOffset, 5)
        await vm.previousPage()
        XCTAssertEqual(vm.pageOffset, 0)
        XCTAssertEqual(driver.findCalls.map(\.skip), [0, 5, 0])
    }

    func testFindFailureSurfacesError() async {
        let driver = StubDocumentDriver()
        driver.findShouldThrow = .syntax("bad filter")
        let vm = await browseCollection(driver)
        XCTAssertTrue(vm.documents.isEmpty)
        XCTAssertEqual(vm.resultError, DatabaseError.syntax("bad filter").message)
    }

    func testValidateJSONRejectsMalformed() {
        XCTAssertNotNil(DocumentViewModel.validateJSON("{not json"))
        XCTAssertNotNil(DocumentViewModel.validateJSON("[1,2]"))
        XCTAssertNotNil(DocumentViewModel.validateJSON("   "))
        XCTAssertNil(DocumentViewModel.validateJSON(#"{"a":1}"#))
    }

    func testInsertRejectsMalformedWithoutCallingDriver() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        let ok = await vm.insert(json: "{bad")
        XCTAssertFalse(ok)
        XCTAssertTrue(driver.insertCalls.isEmpty)
        XCTAssertNotNil(vm.editError)
    }

    func testInsertValidDocumentCallsDriverAndReloads() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        let before = driver.findCalls.count
        let ok = await vm.insert(json: #"{"name":"z"}"#)
        XCTAssertTrue(ok)
        XCTAssertEqual(driver.insertCalls, [#"{"name":"z"}"#])
        XCTAssertEqual(driver.findCalls.count, before + 1)
    }

    func testUpdateAndDeletePassRecordToDriver() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        let record = vm.documents[0]
        _ = await vm.update(record: record, json: #"{"name":"y"}"#)
        XCTAssertEqual(driver.updateCalls.first?.record, record)
        _ = await vm.delete(record: record)
        XCTAssertEqual(driver.deleteCalls, [record])
    }

    func testWriteFailureSurfacesEditError() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        driver.writeShouldThrow = .connection("write rejected")
        let ok = await vm.insert(json: #"{"a":1}"#)
        XCTAssertFalse(ok)
        XCTAssertEqual(vm.editError, DatabaseError.connection("write rejected").message)
    }

    func testDeselectResetsState() async {
        let vm = await browseCollection(StubDocumentDriver())
        vm.deselect()
        XCTAssertEqual(vm.connection, .idle)
        XCTAssertNil(vm.selectedProfile)
        XCTAssertTrue(vm.documents.isEmpty)
        XCTAssertTrue(vm.collections.isEmpty)
    }

    func testCreateCollectionCallsDriverAndReloads() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        let ok = await vm.createCollection(name: "events")
        XCTAssertTrue(ok)
        XCTAssertEqual(driver.createdCollections, ["events"])
    }

    func testCreateCollectionRejectsEmptyName() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        let ok = await vm.createCollection(name: "   ")
        XCTAssertFalse(ok)
        XCTAssertTrue(driver.createdCollections.isEmpty)
        XCTAssertNotNil(vm.editError)
    }

    func testDropCollectionCallsDriver() async {
        let driver = StubDocumentDriver()
        let vm = await browseCollection(driver)
        let ok = await vm.dropCollection("users")
        XCTAssertTrue(ok)
        XCTAssertEqual(driver.droppedCollections, ["users"])
    }

    func testUnsupportedEngineFailsCleanly() async {
        let vm = DocumentViewModel(makeDriver: { _, _ in nil }, passwordFor: { _ in nil })
        await vm.select(profile: .managedMySQL)
        if case .failed = vm.connection {} else { XCTFail("expected failed connection") }
        XCTAssertFalse(vm.isBusy)
    }
}
