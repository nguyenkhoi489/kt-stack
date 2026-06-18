import Foundation

struct InstallCommandRunner: Sendable {
    struct CommandError: LocalizedError {
        let command: String
        let status: Int32
        let output: String
        var errorDescription: String? { "\(command) failed (exit \(status)). \(output.suffix(600))" }
    }

    let php: URL

    @discardableResult
    func runPHP(_ args: [String], cwd: URL, stdin: String? = nil) throws -> String {
        try run(php, args, cwd: cwd, stdin: stdin)
    }

    @discardableResult
    func run(_ exe: URL, _ args: [String], cwd: URL, stdin: String? = nil) throws -> String {
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        proc.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        let output = Pipe()
        proc.standardOutput = output
        proc.standardError = output
        let input = Pipe()
        proc.standardInput = input
        try proc.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            throw CommandError(command: "\(exe.lastPathComponent) \(args.first ?? "")",
                               status: proc.terminationStatus, output: text)
        }
        return text
    }
}
