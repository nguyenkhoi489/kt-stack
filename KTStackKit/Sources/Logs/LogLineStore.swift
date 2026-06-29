import Foundation

public enum LogSeverity: String, Sendable, CaseIterable {
    case info, warning, error
}

public struct LogLine: Identifiable, Sendable, Hashable {
    public let id: Int
    public let text: String
    public let severity: LogSeverity
}

public final class LogLineStore: @unchecked Sendable {
    public let capacity: Int
    private let lock = NSLock()
    private var lines: [LogLine] = []
    private var nextID = 0

    public init(capacity: Int = 5000) {
        self.capacity = capacity
        lines.reserveCapacity(capacity)
    }

    @discardableResult
    public func append(_ raw: [String]) -> [LogLine] {
        lock.lock(); defer { lock.unlock() }
        for text in raw {
            lines.append(LogLine(id: nextID, text: text, severity: Self.severity(of: text)))
            nextID += 1
        }
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
        return lines
    }

    public func clear() {
        lock.lock(); lines.removeAll(keepingCapacity: true); lock.unlock()
    }

    public func snapshot() -> [LogLine] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }

    public func filtered(_ query: String) -> [LogLine] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let all = snapshot()
        guard !q.isEmpty else { return all }
        return all.filter { $0.text.range(of: q, options: .caseInsensitive) != nil }
    }

    static func severity(of line: String) -> LogSeverity {
        let l = line.lowercased()
        if l.contains("[error]") || l.contains("[emerg]") || l.contains("[crit]") || l.contains("[alert]")
            || l.contains("fatal") || l.contains("error:") || l.contains(" error ") || l.contains("[error:")
        {
            return .error
        }
        if l.contains("[warn]") || l.contains("warning") || l.contains("[notice]") && l.contains("fail") {
            return .warning
        }
        return .info
    }
}
