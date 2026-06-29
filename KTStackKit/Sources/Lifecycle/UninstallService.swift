import Combine
import Foundation
import ServiceManagement

@MainActor
public final class UninstallService: ObservableObject {
    public enum State: Equatable { case idle, running, done, failed(String) }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var log: [String] = []

    private let paths: AppSupportPaths
    private let dns: DNSAutomationService
    private let mkcert: MkcertRunner
    private let agents: LaunchAgentManager

    public init(paths: AppSupportPaths, dns: DNSAutomationService, mkcertBinary: URL) {
        self.paths = paths
        self.dns = dns
        mkcert = MkcertRunner(mkcert: mkcertBinary, caroot: paths.caDir)
        agents = LaunchAgentManager(paths: paths)
    }

    public func uninstall() {
        guard state != .running else { return }
        state = .running
        log = []
        record("Starting uninstall…")

        dns.disable()
        record("Removing .\(dns.tld) DNS resolver…")

        do {
            try ShellPathManager(paths: paths).disable()
            record("Removed shell PATH integration.")
        } catch {
            record("Shell PATH cleanup warning: \(error.localizedDescription)")
        }

        let agents = agents, mkcert = mkcert, root = paths.root, resolverTLD = dns.tld
        Task.detached(priority: .userInitiated) { [weak self] in
            agents.bootoutAll()
            await self?.record("Stopped all launchd services.")

            var caNote = "Removed local CA trust (System Keychain + Firefox/NSS)."
            if mkcert.caExists {
                do { try mkcert.uninstall() } catch { caNote = "CA untrust warning: \(error.localizedDescription)" }
            }
            await self?.record(caNote)

            Self.unregisterDaemonIfSigned()
            await self?.record("Unregistered privileged helper (if installed).")

            var failure: String?
            do {
                if FileManager.default.fileExists(atPath: root.path) {
                    try FileManager.default.removeItem(at: root)
                }
            } catch { failure = error.localizedDescription }

            let resolverLeft = FileManager.default.fileExists(atPath: DNSConstants.resolverPath(for: resolverTLD))

            await MainActor.run {
                self?.record(
                    failure == nil
                        ? "Removed all app-support data, runtimes and databases."
                        : "Data removal warning: \(failure!)"
                )
                if resolverLeft {
                    self?.record("Warning: \(DNSConstants.resolverPath(for: resolverTLD)) still present — re-run, or remove it with sudo.")
                }
                if let failure {
                    self?.state = .failed(failure)
                } else if resolverLeft {
                    self?.state = .failed("DNS resolver not removed")
                } else {
                    self?.state = .done
                }
            }
        }
    }

    private func record(_ message: String) {
        log.append(message)
    }

    private nonisolated static func unregisterDaemonIfSigned() {
        guard HelperIdentity.hasSigningIdentity, #available(macOS 13.0, *) else { return }
        try? SMAppService.daemon(plistName: "com.ktstack.helper.plist").unregister()
    }
}
