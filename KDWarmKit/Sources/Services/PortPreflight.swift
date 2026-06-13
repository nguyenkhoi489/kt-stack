import Foundation

/// Pre-flight check run before nginx tries to bind a port. The most common first-run
/// failure is macOS's built-in Apache squatting on `:80`, so a raw "bind: address already
/// in use" is translated into a named, actionable conflict message.
///
/// This is the first instance of the check that Phase 4/6 generalise across `:80`, `:443`,
/// `:53`. It probes the SAME wildcard address nginx will use (`0.0.0.0`), so the result
/// reflects the real bind nginx will attempt.
public struct PortPreflight {
    public enum Outcome: Equatable, Sendable {
        case available
        /// Port is held. `process` is the owning command (from lsof) when known.
        case inUse(process: String?, message: String)
        /// Bind failed for a reason other than a conflict (e.g. unexpected EACCES).
        case blocked(message: String)
    }

    public init() {}

    public func check(port: Int) -> Outcome {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return .blocked(message: "Could not create a probe socket.") }
        defer { close(fd) }

        // Match how nginx binds (SO_REUSEADDR) so a socket lingering in TIME_WAIT — e.g. right after
        // we boot our own server out during a restart — is not misreported as a foreign conflict.
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY                 // 0.0.0.0 — same as nginx's listen

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bound == 0 { return .available }

        let err = errno
        if err == EADDRINUSE {
            let owner = Self.listeningProcess(onPort: port)
            return .inUse(process: owner, message: Self.conflictMessage(port: port, process: owner))
        }
        if err == EACCES {
            return .blocked(message: "Permission denied binding 0.0.0.0:\(port). "
                + "Expected the wildcard bind to succeed without root — check for a security policy change.")
        }
        return .blocked(message: "Could not bind 0.0.0.0:\(port): \(String(cString: strerror(err))).")
    }

    /// Convenience: pre-flight every port in `ports`, returning the first conflict (or `.available`).
    /// Generalises the single-port check across the service ports (80/443/3306/5432/6379/8025/1025).
    public func firstConflict(in ports: [Int]) -> Outcome {
        for port in ports {
            let outcome = check(port: port)
            if outcome != .available { return outcome }
        }
        return .available
    }

    /// Build a human, named-conflict message. Apple's Apache (`httpd`) is the usual suspect on :80;
    /// a pre-existing Homebrew DB is the usual suspect on a DB port.
    static func conflictMessage(port: Int, process: String?) -> String {
        switch process?.lowercased() {
        case "httpd":
            return "Apache (macOS built-in) is using port \(port). Stop it with "
                + "`sudo apachectl stop`, or change KDWarm's port in Settings."
        case "mysqld", "mariadbd":
            return "Another MySQL/MariaDB is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop mysql`) or change KDWarm's port in Settings."
        case "postgres":
            return "Another PostgreSQL is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop postgresql`) or change KDWarm's port in Settings."
        case "redis-server":
            return "Another Redis is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop redis`) or change KDWarm's port in Settings."
        case "mongod":
            return "Another MongoDB is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop mongodb-community`)."
        case .some(let name):
            return "Port \(port) is already in use by “\(name)”. Stop that process or change KDWarm's port."
        case .none:
            return "Port \(port) is already in use by another process. Stop it or change KDWarm's port."
        }
    }

    /// Best-effort: ask `lsof` which command is LISTENing on the port. Returns nil if lsof
    /// is unavailable or reports nothing.
    static func listeningProcess(onPort port: Int) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-F", "c"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        // `-F c` prints lines like `cHTTPd` / `cnginx`; take the first command field.
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("c") {
            return String(line.dropFirst())
        }
        return nil
    }
}
