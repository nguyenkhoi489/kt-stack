import Foundation

public struct ServiceMetricsSample: Sendable, Hashable {
    public let cpuPercent: Double
    public let memoryBytes: Int64
}

struct ParsedServiceProcess: Equatable {
    let pid: Int32
    let rssBytes: Int64
    let cpuSeconds: Double
    let basename: String
}

struct ProcessCPUSample: Equatable {
    let cpuSeconds: Double
    let sampledAt: Date
}

final class ServiceMetricsSampler {
    private var previous: [Int32: ProcessCPUSample] = [:]

    private static let kindByBinary: [String: ServiceKind] = {
        var map: [String: ServiceKind] = [:]
        for kind in ServiceKind.allCases where kind.binaryName != nil {
            map[kind.binaryName!] = kind
        }
        return map
    }()

    func sample() async -> [ServiceKind: ServiceMetricsSample] {
        let raw = await Self.runPS()
        let now = Date()
        let outcome = Self.aggregate(current: Self.parse(raw), previous: previous, now: now)
        previous = outcome.nextPrevious
        return outcome.metrics
    }

    static func aggregate(
        current: [ParsedServiceProcess],
        previous: [Int32: ProcessCPUSample],
        now: Date
    )
        -> (metrics: [ServiceKind: ServiceMetricsSample], nextPrevious: [Int32: ProcessCPUSample])
    {
        var cpuByKind: [ServiceKind: Double] = [:]
        var memByKind: [ServiceKind: Int64] = [:]
        var nextPrevious: [Int32: ProcessCPUSample] = [:]

        for row in current {
            nextPrevious[row.pid] = ProcessCPUSample(cpuSeconds: row.cpuSeconds, sampledAt: now)
            guard let kind = kindByBinary[row.basename] else { continue }
            memByKind[kind, default: 0] += row.rssBytes
            if let prior = previous[row.pid] {
                let wall = now.timeIntervalSince(prior.sampledAt)
                let delta = row.cpuSeconds - prior.cpuSeconds
                if wall > 0, delta > 0 {
                    cpuByKind[kind, default: 0] += delta / wall * 100
                }
            }
        }

        var metrics: [ServiceKind: ServiceMetricsSample] = [:]
        for kind in Set(cpuByKind.keys).union(memByKind.keys) {
            metrics[kind] = ServiceMetricsSample(
                cpuPercent: cpuByKind[kind] ?? 0,
                memoryBytes: memByKind[kind] ?? 0
            )
        }
        return (metrics, nextPrevious)
    }

    static func parse(_ raw: String) -> [ParsedServiceProcess] {
        var rows: [ParsedServiceProcess] = []
        for line in raw.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4,
                  let pid = Int32(fields[0]),
                  let rssKiB = Int64(fields[1]),
                  let cpuSeconds = parseCPUTime(String(fields[2])) else { continue }
            let command = fields[3...].joined(separator: " ")
            rows.append(ParsedServiceProcess(
                pid: pid,
                rssBytes: rssKiB * 1024,
                cpuSeconds: cpuSeconds,
                basename: serviceName(from: command)
            ))
        }
        return rows
    }

    static func serviceName(from command: String) -> String {
        if command.hasPrefix("/") {
            return (command as NSString).lastPathComponent
        }
        if let colon = command.firstIndex(of: ":") {
            let head = String(command[..<colon])
            if !head.contains("/"), !head.contains(" ") {
                return head
            }
        }
        if let space = command.firstIndex(of: " ") {
            return (String(command[..<space]) as NSString).lastPathComponent
        }
        return (command as NSString).lastPathComponent
    }

    static func parseCPUTime(_ value: String) -> Double? {
        var days = 0.0
        var rest = Substring(value)
        if let dash = value.firstIndex(of: "-") {
            days = Double(value[..<dash]) ?? 0
            rest = value[value.index(after: dash)...]
        }
        let parts = rest.split(separator: ":")
        guard !parts.isEmpty else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let component = Double(part) else { return nil }
            seconds = seconds * 60 + component
        }
        return days * 86400 + seconds
    }

    private static func runPS() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/ps")
                process.arguments = ["-axo", "pid=,rss=,cputime=,comm="]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do { try process.run() } catch {
                    continuation.resume(returning: "")
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
