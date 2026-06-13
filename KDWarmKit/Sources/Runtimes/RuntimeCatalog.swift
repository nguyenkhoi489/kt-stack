import Foundation

/// A language runtime KDWarm can manage. PHP is bundled (staged from the app Resources into the
/// runtimes layout); Node + the on-demand languages are downloaded into the same layout.
public enum RuntimeLanguage: String, CaseIterable, Sendable, Identifiable, Hashable {
    case php, node, python, go, ruby, java

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .php: return "PHP"; case .node: return "Node.js"; case .python: return "Python"
        case .go: return "Go"; case .ruby: return "Ruby"; case .java: return "Java"
        }
    }

    public var symbolName: String {
        switch self {
        case .php:    return "chevron.left.forwardslash.chevron.right"
        case .node:   return "shippingbox"
        case .python: return "tortoise.fill"
        case .go:     return "hare.fill"
        case .ruby:   return "diamond.fill"
        case .java:   return "cup.and.saucer.fill"
        }
    }

    /// No runtime ships in the DMG — every language (PHP included) installs on demand from the hosted
    /// GitHub Release, keeping the app lean. Drives the card's "On-demand" badge.
    public var isBundled: Bool { false }

    /// Relative path (within a `runtimes/<lang>/<version>/` dir) of the executable that proves the
    /// version is installed and runnable.
    public var executableRelPath: String {
        switch self {
        case .php:    return "bin/php-fpm"
        case .node:   return "bin/node"
        case .python: return "bin/python3"
        case .go:     return "bin/go"
        case .ruby:   return "bin/ruby"
        case .java:   return "bin/java"
        }
    }
}

/// A downloadable runtime build: an official archive URL + its expected SHA-256. Arch-specific
/// (arm64 here); a universal/x86_64 manifest layer is added when upstream lacks arm64 builds.
public struct RuntimeRelease: Sendable, Hashable, Identifiable {
    public let language: RuntimeLanguage
    public let version: String
    public let url: URL
    public let sha256: String

    public var id: String { "\(language.rawValue)-\(version)" }

    public init(language: RuntimeLanguage, version: String, url: String, sha256: String) {
        self.language = language
        self.version = version
        self.url = URL(string: url)!
        self.sha256 = sha256
    }
}

/// Installed-runtime discovery + the static download manifest. Installed versions are found by
/// scanning `runtimes/<lang>/<version>/` for the language's marker executable; the manifest lists
/// verified official builds (real URLs + checksums) for on-demand install.
public struct RuntimeCatalog: Sendable {
    private let paths: AppSupportPaths
    public init(paths: AppSupportPaths) { self.paths = paths }

    /// Installed versions of `lang`, sorted — a version counts only if its marker binary is present.
    public func installedVersions(_ lang: RuntimeLanguage) -> [String] {
        let root = paths.runtimeLangRoot(lang.rawValue)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return entries
            .filter { fm.isExecutableFile(atPath: root.appendingPathComponent($0)
                .appendingPathComponent(lang.executableRelPath).path) }
            .sorted()
    }

    public func isInstalled(_ lang: RuntimeLanguage, _ version: String) -> Bool {
        installedVersions(lang).contains(version)
    }

    /// Downloadable builds for `lang` (excludes already-installed versions).
    public func availableReleases(_ lang: RuntimeLanguage) -> [RuntimeRelease] {
        let installed = Set(installedVersions(lang))
        return Self.manifest.filter { $0.language == lang && !installed.contains($0.version) }
    }

    /// Verified official builds (arm64 / Apple Silicon). Pinned versions — the manifest is versioned
    /// and refreshed as upstream releases move; a stale URL surfaces as a download failure (retryable).
    /// Ruby/Java have no entries yet (shown as on-demand with nothing to install until added).
    public static let manifest: [RuntimeRelease] = [
        // Self-built, relocatable, Developer-ID-signed + notarized static PHP (php.net ships source
        // only — no upstream macOS binary). Hosted on the project's GitHub Releases. Every version,
        // incl. the default 8.4, installs on demand from here — nothing is bundled in the DMG.
        RuntimeRelease(language: .php, version: "8.4",
                       url: "https://github.com/nguyenkhoi489/kd-warm/releases/download/binaries-v1/php-8.4-arm64.tar.gz",
                       sha256: "a1084e4008299242ab6cad63b4029a6622571b43664b9c840ad2ea2151f4484b"),
        RuntimeRelease(language: .php, version: "8.3",
                       url: "https://github.com/nguyenkhoi489/kd-warm/releases/download/binaries-v1/php-8.3-arm64.tar.gz",
                       sha256: "6df25fee653c6f76a33f6f2c9c5cc6dda457b416c1b5542bc26a9fec403c6734"),
        RuntimeRelease(language: .php, version: "8.1",
                       url: "https://github.com/nguyenkhoi489/kd-warm/releases/download/binaries-v1/php-8.1-arm64.tar.gz",
                       sha256: "2ac560a63a85503ea651ad6ee25a21e939c4388332208e0f85887210b091d668"),
        RuntimeRelease(language: .go, version: "1.26.4",
                       url: "https://go.dev/dl/go1.26.4.darwin-arm64.tar.gz",
                       sha256: "b62ad2b6d7d2464f12a5bcad7ff47f19d08325773b5efd21610e445a05a9bf53"),
        RuntimeRelease(language: .node, version: "22.22.3",
                       url: "https://nodejs.org/dist/v22.22.3/node-v22.22.3-darwin-arm64.tar.gz",
                       sha256: "0da7ff74ef8611328c8212f17943368713a2ad953fb7d89a8c8a0eae87c23207"),
        RuntimeRelease(language: .python, version: "3.12.13",
                       url: "https://github.com/astral-sh/python-build-standalone/releases/download/20260610/cpython-3.12.13%2B20260610-aarch64-apple-darwin-install_only.tar.gz",
                       sha256: "e18ddd4c1e8f4a1d6c4590b37f423d76aec734447edc20ed08e93983d95f2132"),
    ]
}
