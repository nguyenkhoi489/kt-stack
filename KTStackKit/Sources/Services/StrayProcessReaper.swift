import Foundation

enum StrayProcessReaper {
    static func pids(matching programPath: String) -> [Int32] {
        let res = run("/usr/bin/pgrep", ["-f", programPath])
        guard res.code == 0 else { return [] }
        let me = getpid()
        return res.out
            .split(whereSeparator: { $0 == "\n" || $0 == " " })
            .compactMap { Int32($0) }
            .filter { $0 != me }
    }

    static func terminate(_ pids: [Int32], graceSeconds: TimeInterval = 5) {
        guard !pids.isEmpty else { return }
        for pid in pids {
            kill(pid, SIGTERM)
        }

        let deadline = Date().addingTimeInterval(graceSeconds)
        while Date() < deadline {
            if pids.allSatisfy({ kill($0, 0) != 0 }) { return }
            usleep(200_000)
        }
        for pid in pids where kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> (code: Int32, out: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
