import Combine
import Foundation

@MainActor
public final class AppPreferences: ObservableObject {
    public static let defaultTLD = "test"

    public static let safeTLDs = ["test", "home.arpa", "internal"]

    public static var defaultSitesRootPath: String {
        AppSupportPaths.defaultSitesRoot.path
    }

    public enum ReleaseChannel: String, CaseIterable, Sendable, Identifiable {
        case stable, beta
        public var id: String {
            rawValue
        }

        public var label: String {
            self == .stable ? "Stable" : "Beta"
        }
    }

    @Published public private(set) var sitesRootPath: String
    @Published public private(set) var tld: String

    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    @Published public var autoStartServer: Bool {
        didSet { defaults.set(autoStartServer, forKey: Key.autoStartServer) }
    }

    @Published public var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar) }
    }

    @Published public var serveHTTPSByDefault: Bool {
        didSet { defaults.set(serveHTTPSByDefault, forKey: Key.serveHTTPS) }
    }

    @Published public var automaticUpdates: Bool {
        didSet { defaults.set(automaticUpdates, forKey: Key.automaticUpdates) }
    }

    @Published public var releaseChannel: ReleaseChannel {
        didSet { defaults.set(releaseChannel.rawValue, forKey: Key.releaseChannel) }
    }

    // One-shot: gates the first-launch DNS setup prompt so it shows once, not every open.
    @Published public var hasSeenDNSSetup: Bool {
        didSet { defaults.set(hasSeenDNSSetup, forKey: Key.hasSeenDNSSetup) }
    }

    // Writes verbose service-startup diagnostics to logs/diagnostics.log. Read live by
    // ServiceDiagnostics.isEnabled off UserDefaults.standard, so the key value is frozen.
    @Published public var devMode: Bool {
        didSet { defaults.set(devMode, forKey: Key.devMode) }
    }

    private let defaults: UserDefaults
    private enum Key {
        static let sitesRoot = "KTStack.sitesRootPath"
        static let tld = "KTStack.tld"
        static let launchAtLogin = "KTStack.launchAtLogin"
        static let autoStartServer = "KTStack.autoStartServer"
        static let showInMenuBar = "KTStack.showInMenuBar"
        static let serveHTTPS = "KTStack.serveHTTPSByDefault"
        static let automaticUpdates = "KTStack.automaticUpdates"
        static let releaseChannel = "KTStack.releaseChannel"
        static let hasSeenDNSSetup = "KTStack.hasSeenDNSSetup"
        static let devMode = "KTStack.devMode"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sitesRootPath = defaults.string(forKey: Key.sitesRoot) ?? Self.defaultSitesRootPath
        let stored = defaults.string(forKey: Key.tld) ?? Self.defaultTLD

        tld = Self.isValidTLD(stored) ? stored : Self.defaultTLD
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        autoStartServer = defaults.bool(forKey: Key.autoStartServer)
        showInMenuBar = defaults.object(forKey: Key.showInMenuBar) as? Bool ?? true
        serveHTTPSByDefault = defaults.object(forKey: Key.serveHTTPS) as? Bool ?? true
        automaticUpdates = defaults.object(forKey: Key.automaticUpdates) as? Bool ?? true
        releaseChannel = ReleaseChannel(rawValue: defaults.string(forKey: Key.releaseChannel) ?? "") ?? .stable
        hasSeenDNSSetup = defaults.bool(forKey: Key.hasSeenDNSSetup)
        devMode = defaults.bool(forKey: Key.devMode)
    }

    public func setLaunchAtLogin(_ on: Bool) {
        launchAtLogin = on
    }

    public func setReleaseChannel(_ channel: ReleaseChannel) {
        releaseChannel = channel
    }

    public var sitesRootURL: URL {
        URL(fileURLWithPath: sitesRootPath)
    }

    public func setSitesRootPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sitesRootPath = trimmed
        defaults.set(trimmed, forKey: Key.sitesRoot)
    }

    @discardableResult
    public func setTLD(_ raw: String) -> Bool {
        let candidate = raw.trimmingCharacters(in: .whitespaces)
        guard candidate != tld else { return true }
        guard Self.isValidTLD(candidate) else { return false }
        tld = candidate
        defaults.set(candidate, forKey: Key.tld)
        return true
    }

    public static func isValidTLD(_ s: String) -> Bool {
        DNSConstants.isValidTLD(s)
    }
}
