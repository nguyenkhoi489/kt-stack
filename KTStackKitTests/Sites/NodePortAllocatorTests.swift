import XCTest
@testable import KTStackKit

final class NodePortAllocatorTests: XCTestCase {
    private let allocator = NodePortAllocator()

    func testPicksSmallestFreePortAvoidingExisting() {
        let port = allocator.allocate(existing: [3000, 3001], range: 3000...3005, reserved: []) { _ in true }
        XCTAssertEqual(port, 3002)
    }

    func testSkipsReservedServicePorts() {
        let port = allocator.allocate(existing: [], range: 3305...3307,
                                      reserved: [3306]) { _ in true }
        XCTAssertEqual(port, 3305)
        let next = allocator.allocate(existing: [3305], range: 3305...3307,
                                      reserved: [3306]) { _ in true }
        XCTAssertEqual(next, 3307)
    }

    func testDefaultReservedExcludesMySQLPortInsideRange() {
        let chosen = allocator.allocate(existing: Array(3000...3305), range: 3000...3307) { _ in true }
        XCTAssertEqual(chosen, 3307, "3306 is reserved by default so the next free port is 3307")
    }

    func testReturnsNilWhenExhausted() {
        let port = allocator.allocate(existing: [3000, 3001], range: 3000...3001, reserved: []) { _ in true }
        XCTAssertNil(port)
    }

    func testSkipsPortsReportedBusy() {
        let busy: Set<Int> = [3000, 3001]
        let port = allocator.allocate(existing: [], range: 3000...3002, reserved: []) { !busy.contains($0) }
        XCTAssertEqual(port, 3002)
    }
}
