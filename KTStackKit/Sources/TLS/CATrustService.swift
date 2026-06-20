import Foundation
import Combine
import CryptoKit

@MainActor
public final class CATrustService: ObservableObject {
    public enum Status: Equatable, Sendable {
        case notInstalled        // no CA generated yet
        case untrusted           // CA exists on disk but not trusted in the System Keychain
        case trusted             // CA present in the System Keychain
    }

    @Published public private(set) var status: Status = .notInstalled
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastError: String?

    public let usesHelper = HelperIdentity.hasSigningIdentity

    nonisolated public let runner: MkcertRunner
    nonisolated private let paths: AppSupportPaths

    public init(paths: AppSupportPaths, mkcertBinary: URL) {
        self.paths = paths
        self.runner = MkcertRunner(mkcert: mkcertBinary, caroot: paths.caDir)
        refresh()
    }

    public var isTrusted: Bool { status == .trusted }

    public func refresh() {
        guard runner.caExists else { status = .notInstalled; return }
        status = Self.isTrustedInSystemKeychain(caCert: paths.caRootCert) ? .trusted : .untrusted
    }

    public func refreshAsync() async {
        guard runner.caExists else { status = .notInstalled; return }
        let caCert = paths.caRootCert
        let trusted = await Task.detached { Self.isTrustedInSystemKeychain(caCert: caCert) }.value
        status = trusted ? .trusted : .untrusted
    }

    public func install() { run { try self.runner.install() } }

   
    public func untrust() { run { try self.runner.uninstall() } }

    public func ensureTrusted() throws {
        if !isTrusted { try runner.install() }
    }

    private func run(_ work: @escaping @Sendable () throws -> Void) {
        guard !isBusy else { return }
        isBusy = true; lastError = nil
        Task.detached(priority: .userInitiated) {
            var failure: String?
            do { try work() } catch { failure = error.localizedDescription }
            await MainActor.run {
                self.isBusy = false
                if let failure { self.lastError = failure }
                self.refresh()
            }
        }
    }

    // MARK: - Trust query

    public nonisolated static func isTrustedInSystemKeychain(caCert: URL) -> Bool {
        guard let pem = try? Data(contentsOf: caCert),
              let der = CertMinter.pemToDER(pem) else { return false }
        let sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-certificate", "-a", "-Z", "/Library/Keychains/System.keychain"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return out.uppercased().contains(sha1)
    }
}
