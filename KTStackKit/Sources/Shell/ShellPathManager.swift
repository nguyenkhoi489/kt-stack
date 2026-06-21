import Foundation

public final class ShellPathManager: @unchecked Sendable {
    public struct Status: Sendable, Equatable {
        public let enabled: Bool
        public let shellsPatched: [String]
    }

    public enum ShellError: LocalizedError {
        case ownership(String)
        case helperMissing(String)
        public var errorDescription: String? {
            switch self {
            case .ownership(let path): return "Refusing to use shim directory \(path): it is not owned by the current user."
            case .helperMissing(let path): return "Resolver helper not found at \(path)."
            }
        }
    }

    private let paths: AppSupportPaths
    private let helperSource: URL?
    private let home: URL

    public init(paths: AppSupportPaths, helperSource: URL? = nil,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.paths = paths
        self.helperSource = helperSource
        self.home = home
    }

    private var exportLine: String { "export PATH=\"\(paths.shimBinDir.path):$PATH\"" }

    private var rcFiles: [URL] {
        let fm = FileManager.default
        var files = [home.appendingPathComponent(".zshrc")]
        for candidate in [".bashrc", ".bash_profile"] {
            let url = home.appendingPathComponent(candidate)
            if fm.fileExists(atPath: url.path) { files.append(url) }
        }
        return files
    }

    public func enable(provisionComposer: Bool = true) async throws {
        try prepareShimDir()
        try ShellShimWriter(paths: paths).writeShims()
        if provisionComposer {
            do { _ = try await ComposerProvisioner(paths: paths).provision() }
            catch { NSLog("KTStack: composer provisioning skipped — \(error.localizedDescription)") }
        }
        let patcher = ShellRCPatcher(exportLine: exportLine)
        for rc in rcFiles { try patch(rc, with: patcher) }
    }

    public func disable() throws {
        let patcher = ShellRCPatcher(exportLine: exportLine)
        let fm = FileManager.default
        var firstError: Error?
        for rc in rcFiles where fm.fileExists(atPath: rc.path) {
            do {
                let content = (try? String(contentsOf: rc, encoding: .utf8)) ?? ""
                let updated = try patcher.contentRemovingBlock(from: content, file: rc.lastPathComponent)
                try backup(rc)
                try updated.data(using: .utf8)!.write(to: rc, options: .atomic)
            } catch { if firstError == nil { firstError = error } }
        }
        if fm.fileExists(atPath: paths.shimBinDir.path) { try? fm.removeItem(at: paths.shimBinDir) }
        if let firstError { throw firstError }
    }

    public func composerProvisioned() -> Bool {
        ComposerProvisioner(paths: paths).isProvisioned
    }

    public func status() -> Status {
        let patcher = ShellRCPatcher(exportLine: exportLine)
        var patched: [String] = []
        for rc in rcFiles {
            guard let content = try? String(contentsOf: rc, encoding: .utf8) else { continue }
            if patcher.containsValidBlock(in: content, file: rc.lastPathComponent) {
                patched.append(rc.lastPathComponent)
            }
        }
        let helperReady = FileManager.default.fileExists(
            atPath: paths.shimBinDir.appendingPathComponent("ktstack-resolve").path)
        return Status(enabled: helperReady && !patched.isEmpty, shellsPatched: patched)
    }

    private func prepareShimDir() throws {
        let fm = FileManager.default
        let dir = paths.shimBinDir
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o755])
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        let attrs = try fm.attributesOfItem(atPath: dir.path)
        if let owner = attrs[.ownerAccountID] as? NSNumber, owner.uint32Value != getuid() {
            throw ShellError.ownership(dir.path)
        }
        guard let helperSource, fm.isExecutableFile(atPath: helperSource.path) else {
            throw ShellError.helperMissing(helperSource?.path ?? "ktstack-resolve")
        }
        let dest = dir.appendingPathComponent("ktstack-resolve")
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: helperSource, to: dest)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
    }

    private func patch(_ url: URL, with patcher: ShellRCPatcher) throws {
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = try patcher.contentWithBlock(in: content, file: url.lastPathComponent)
        try backup(url)
        try updated.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    private func backup(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).ktstack.bak-\(stamp)")
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: url, to: dest)
    }
}
