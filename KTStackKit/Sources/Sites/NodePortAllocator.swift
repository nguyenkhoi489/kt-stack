import Foundation

public struct NodePortAllocator: Sendable {
    public static let reservedPorts: Set<Int> = [53, 3306, 5432, 6379, 8025, 27017]

    public init() {}

    public func allocate(existing: [Int],
                         range: ClosedRange<Int> = 3000...3999,
                         reserved: Set<Int> = NodePortAllocator.reservedPorts,
                         isFree: (Int) -> Bool) -> Int? {
        let excluded = Set(existing).union(reserved)
        for port in range where !excluded.contains(port) && isFree(port) {
            return port
        }
        return nil
    }
}
