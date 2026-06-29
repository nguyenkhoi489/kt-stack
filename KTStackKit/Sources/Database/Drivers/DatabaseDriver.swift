import Foundation

public protocol DatabaseDriver: Sendable {
    var kind: DatabaseKind { get }

    func ping() async throws
}
