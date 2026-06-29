import XCTest
@testable import KTStackKit

/// Real-Keychain coverage of password CRUD. Uses a dedicated test service string so it never touches
/// the production `com.ktstack.db` items, and tears down every account it creates. The production
/// security attrs (this-device-only, non-synchronizable) are asserted via the store's own constants —
/// the test reads them rather than overriding them, so a weakening-for-convenience change fails here.
final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore(service: "com.ktstack.db.tests")
    private let account = "test-\(UUID().uuidString)"

    override func tearDown() {
        try? store.delete(account: account)
        super.tearDown()
    }

    func testSetThenGetReturnsStoredPassword() throws {
        try store.set("s3cr3t", account: account)
        XCTAssertEqual(try store.get(account: account), "s3cr3t")
    }

    func testSetOverwritesExistingPassword() throws {
        try store.set("first", account: account)
        try store.set("second", account: account) // update, not duplicate-insert
        XCTAssertEqual(try store.get(account: account), "second")
    }

    func testGetMissingAccountReturnsNil() throws {
        XCTAssertNil(try store.get(account: "absent-\(UUID().uuidString)"))
    }

    func testDeleteRemovesPassword() throws {
        try store.set("gone", account: account)
        try store.delete(account: account)
        XCTAssertNil(try store.get(account: account))
    }

    func testDeleteMissingAccountIsNoError() throws {
        XCTAssertNoThrow(try store.delete(account: "absent-\(UUID().uuidString)"))
    }

    func testProductionSecurityAttrsArePinned() {
        // The accessibility class must be the most restrictive (unlocked, this device only) and
        // iCloud Keychain sync must be off — DB credentials never leave the machine.
        XCTAssertEqual(KeychainStore.accessibleAttr, kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        XCTAssertFalse(KeychainStore.synchronizable)
    }
}
