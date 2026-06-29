import Foundation

struct InstallCommandRunner {
    struct CommandError: LocalizedError {
        let command: String
        let status: Int32
        let output: String
        var errorDescription: String? {
            "\(command) failed (exit \(status)). \(output.suffix(600))"
        }
    }

    let php: URL
    let phpIni: URL?
    let phpScanDir: URL?

    init(php: URL, phpIni: URL? = nil) {
        self.php = php
        self.phpIni = phpIni
        phpScanDir = php.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("conf.d", isDirectory: true)
    }

    @discardableResult
    func runPHP(_ args: [String], cwd: URL, stdin: String? = nil) throws -> String {
        try run(php, phpArguments(args), cwd: cwd, stdin: stdin)
    }

    func phpArguments(_ args: [String]) -> [String] {
        guard let phpIni, FileManager.default.fileExists(atPath: phpIni.path) else { return args }
        return ["-c", phpIni.path] + args
    }

    func loadedModules(cwd: URL) throws -> Set<String> {
        try Set(PHPModules.parse(runPHP(["-m"], cwd: cwd)))
    }

    @discardableResult
    func run(_ exe: URL, _ args: [String], cwd: URL, stdin: String? = nil) throws -> String {
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        proc.currentDirectoryURL = cwd
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": NSHomeDirectory()]
        if let phpScanDir, FileManager.default.fileExists(atPath: phpScanDir.path) {
            environment["PHP_INI_SCAN_DIR"] = phpScanDir.path
            let modulesDir = phpScanDir.deletingLastPathComponent().appendingPathComponent("modules", isDirectory: true)
            for (key, value) in ImageMagickEnvironment.variables(modulesDir: modulesDir) {
                environment[key] = value
            }
        }
        proc.environment = environment
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
            throw CommandError(
                command: "\(exe.lastPathComponent) \(args.first ?? "")",
                status: proc.terminationStatus,
                output: text
            )
        }
        return text
    }
}
