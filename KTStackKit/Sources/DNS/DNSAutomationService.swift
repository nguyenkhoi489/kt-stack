import Combine
import Foundation

@MainActor
public final class DNSAutomationService: ObservableObject {
    public enum Status: Equatable, Sendable {
        case unknown
        case disabled // no /etc/resolver/test
        case enabled // resolver present
        case conflict(String) // a foreign process holds :53
    }

    @Published public private(set) var status: Status = .unknown
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastError: String?

    public let usesHelper = HelperIdentity.hasSigningIdentity

    public let tld: String

    private nonisolated let fallback: SudoFallbackInstaller
    private nonisolated let port53 = Port53ConflictDetector()
    private nonisolated let helper = HelperConnection()

    public init(bundledDnsmasq: URL, tld: String = AppPreferences.defaultTLD) {
        self.tld = tld
        fallback = SudoFallbackInstaller(bundledDnsmasq: bundledDnsmasq, tld: tld)
        refresh()
    }

    private enum Op { case enable, disable, reset }

    public func refresh() {
        if let conflict = port53.check() { status = .conflict(conflict.process); return }
        status = FileManager.default.fileExists(atPath: DNSConstants.resolverPath(for: tld)) ? .enabled : .disabled
    }

    public var isEnabled: Bool {
        status == .enabled
    }

    public func enable() {
        perform(.enable)
    }

    public func disable() {
        perform(.disable)
    }

    public func reset() {
        perform(.reset)
    }

    public func changeTLD(to newTLD: String, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        guard !isBusy else {
            completion(.failure(NSError(
                domain: "KTStack",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Another DNS operation is in progress."]
            )))
            return
        }
        guard newTLD != tld else { completion(.success(())); return }
        if let conflict = port53.check() {
            lastError = conflict.message; status = .conflict(conflict.process)
            completion(.failure(NSError(
                domain: "KTStack",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: conflict.message]
            )))
            return
        }
        isBusy = true; lastError = nil
        let usesHelper = usesHelper, fallback = fallback, helper = helper, old = tld
        Task.detached(priority: .userInitiated) {
            var failure: Error?
            do {
                if usesHelper { try await Self.viaHelperSetTLD(helper, old: old, new: newTLD) }
                else { try fallback.runSetTLDWithAdminPrivileges(old: old, new: newTLD) }
            } catch {
                failure = error
            }
            await MainActor.run {
                self.isBusy = false
                if let failure { self.lastError = failure.localizedDescription; completion(.failure(failure)) }
                else { self.refresh(); completion(.success(())) }
            }
        }
    }

    private func perform(_ op: Op) {
        guard !isBusy else { return }
        if op != .disable, let conflict = port53.check() {
            lastError = conflict.message; status = .conflict(conflict.process); return
        }
        isBusy = true; lastError = nil
        let usesHelper = usesHelper
        let fallback = fallback
        let helper = helper
        let tld = tld
        Task.detached(priority: .userInitiated) {
            var failure: String?
            do {
                if usesHelper { try await Self.viaHelper(helper, op, tld: tld) }
                else { try Self.viaFallback(fallback, op) }
            } catch {
                failure = error.localizedDescription
            }
            await MainActor.run {
                self.isBusy = false
                if let failure { self.lastError = failure }
                self.refresh()
            }
        }
    }

    private nonisolated static func viaFallback(_ f: SudoFallbackInstaller, _ op: Op) throws {
        switch op {
        case .enable: try f.runInstallWithAdminPrivileges()
        case .disable: try f.runUninstallWithAdminPrivileges()
        case .reset: try f.runResetWithAdminPrivileges()
        }
    }

    private nonisolated static func viaHelper(_ helper: HelperConnection, _ op: Op, tld: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let guard1 = ResumeOnce(cont)
            guard let proxy = helper.remoteProxy({ guard1.fail($0) }) else {
                guard1.fail(NSError(
                    domain: "KTStack",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Privileged helper is not available."]
                ))
                return
            }
            let reply: @Sendable (Bool, String?) -> Void = { ok, msg in
                if ok { guard1.succeed() }
                else { guard1.fail(NSError(
                    domain: "KTStack",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: msg ?? "Helper DNS action failed."]
                )) }
            }
            switch op {
            case .enable: proxy.enableDNS(tld: tld, reply: reply)
            case .disable: proxy.disableDNS(tld: tld, reply: reply)
            case .reset: proxy.resetDNS(tld: tld, reply: reply)
            }
        }
    }

    private nonisolated static func viaHelperSetTLD(_ helper: HelperConnection, old: String, new: String) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let guard1 = ResumeOnce(cont)
            guard let proxy = helper.remoteProxy({ guard1.fail($0) }) else {
                guard1.fail(NSError(
                    domain: "KTStack",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Privileged helper is not available."]
                ))
                return
            }
            proxy.setTLD(old: old, new: new) { ok, msg in
                if ok { guard1.succeed() }
                else { guard1.fail(NSError(
                    domain: "KTStack",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: msg ?? "Helper DNS action failed."]
                )) }
            }
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let cont: CheckedContinuation<Void, Error>
        private let lock = NSLock()
        private var done = false
        init(_ cont: CheckedContinuation<Void, Error>) {
            self.cont = cont
        }

        func succeed() {
            fire { cont.resume() }
        }

        func fail(_ error: Error) {
            fire { cont.resume(throwing: error) }
        }

        private func fire(_ block: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }
            done = true; block()
        }
    }
}
