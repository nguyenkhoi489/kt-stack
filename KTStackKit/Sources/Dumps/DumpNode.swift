import Foundation

public indirect enum DumpNode: Sendable {
    case scalar(String)
    case array([(key: String, value: DumpNode)])
    case object(className: String, properties: [(key: String, value: DumpNode)])
    case reference(Int)

    public var displaySummary: String {
        switch self {
        case let .scalar(s): s
        case let .array(items): "array(\(items.count))"
        case let .object(cls, _): cls
        case let .reference(n): "&\(n)"
        }
    }
}
