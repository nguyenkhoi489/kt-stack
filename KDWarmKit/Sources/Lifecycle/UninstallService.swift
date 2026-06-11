import Foundation
import Combine
import ServiceManagement

/// Full uninstall / reset: removes KDWarm's entire footprint so the machine is left clean.
/// Order matters — untrust the CA and disable DNS BEFORE deleting the app-support tree (those steps
/// read material from it). Root-scoped removals (resolver, System-Keychain CA) go through the same
/// helper / sudo-fallback paths the install used; everything else is user-scoped.
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
        self.mkcert = MkcertRunner(mkcert: mkcertBinary, caroot: paths.caDir)
        self.agents = LaunchAgentManager(paths: paths)
    }

    /// Run the full reset. Idempotent-ish: safe to run on an already-clean machine (each step no-ops).
    public func uninstall() {
        guard state != .running else { return }
        state = .running
        log = []
        record("Starting uninstall…")

        // Kick off DNS disable (helper / sudo fallback). It runs in its own task; we verify the
        // resolver is actually gone at the end rather than optimistically claiming success here
        // (a cancelled sudo prompt would otherwise leave /etc/resolver/test behind silently).
        dns.disable()
        record("Removing .test DNS resolver…")

        let agents = self.agents, mkcert = self.mkcert, root = paths.root
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

            // The DNS removal is the one async/privileged step that can be cancelled — verify it.
            let resolverLeft = FileManager.default.fileExists(atPath: DNSConstants.resolverPath)

            await MainActor.run {
                self?.record(failure == nil
                    ? "Removed all app-support data, runtimes and databases."
                    : "Data removal warning: \(failure!)")
                if resolverLeft {
                    self?.record("Warning: \(DNSConstants.resolverPath) still present — re-run, or remove it with sudo.")
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

    private func record(_ message: String) { log.append(message) }

    /// Best-effort SMAppService daemon unregister — only meaningful on a signed build where the
    /// helper was actually registered (the dev/ad-hoc build never registers it).
    private nonisolated static func unregisterDaemonIfSigned() {
        guard HelperIdentity.hasSigningIdentity, #available(macOS 13.0, *) else { return }
        try? SMAppService.daemon(plistName: "com.kdwarm.helper.plist").unregister()
    }
}
