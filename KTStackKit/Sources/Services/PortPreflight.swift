import Foundation

public struct PortPreflight {
    public enum Outcome: Equatable, Sendable {
        case available

        case inUse(process: String?, message: String)

        case blocked(message: String)
    }

    public init() {}

    public func check(port: Int) -> Outcome {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return .blocked(message: "Could not create a probe socket.") }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

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
            return .blocked(
                message: "Permission denied binding 0.0.0.0:\(port). "
                    + "Expected the wildcard bind to succeed without root — check for a security policy change."
            )
        }
        return .blocked(message: "Could not bind 0.0.0.0:\(port): \(String(cString: strerror(err))).")
    }

    public func firstConflict(in ports: [Int]) -> Outcome {
        for port in ports {
            let outcome = check(port: port)
            if outcome != .available { return outcome }
        }
        return .available
    }

    static func conflictMessage(port: Int, process: String?) -> String {
        switch process?.lowercased() {
        case "httpd":
            "Apache (macOS built-in) is using port \(port). Stop it with "
                + "`sudo apachectl stop`, or change KTStack's port in Settings."
        case "mysqld", "mariadbd":
            "Another MySQL/MariaDB is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop mysql`) or change KTStack's port in Settings."
        case "postgres":
            "Another PostgreSQL is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop postgresql`) or change KTStack's port in Settings."
        case "redis-server":
            "Another Redis is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop redis`) or change KTStack's port in Settings."
        case "mongod":
            "Another MongoDB is using port \(port) (often a Homebrew install). "
                + "Stop it (`brew services stop mongodb-community`)."
        case let .some(name):
            "Port \(port) is already in use by “\(name)”. Stop that process or change KTStack's port."
        case .none:
            "Port \(port) is already in use by another process. Stop it or change KTStack's port."
        }
    }

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

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("c") {
            return String(line.dropFirst())
        }
        return nil
    }
}
