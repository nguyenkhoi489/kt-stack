import Foundation

struct WordPressCLI: Sendable {
    static let skipFlags = ["--skip-plugins", "--skip-themes", "--skip-packages"]

    private let runner: InstallCommandRunner
    private let phar: String

    init(php: URL, phpIni: URL?, wpCliPhar: URL) {
        self.runner = InstallCommandRunner(php: php, phpIni: phpIni)
        self.phar = wpCliPhar.path
    }

    @discardableResult
    func run(_ args: [String], in docroot: URL, stdin: String? = nil) throws -> String {
        try runner.runPHP([phar] + args, cwd: docroot, stdin: stdin)
    }

    func pathArgument(_ docroot: URL) -> String {
        "--path=\(docroot.path)"
    }
}
