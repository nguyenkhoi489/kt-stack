import Foundation

public enum DNSConstants {
    public static func resolverPath(for tld: String) -> String {
        "/etc/resolver/\(tld)"
    }

    public struct InvalidTLD: Error, CustomStringConvertible {
        public let value: String
        public init(_ value: String) {
            self.value = value
        }

        public var description: String {
            "Invalid TLD"
        }
    }

    // macOS claims the whole .local domain for mDNS and localhost for loopback; it ignores
    // /etc/resolver entries whose terminal label is one of these, so the resolver never resolves.
    public static let reservedTLDs: Set<String> = ["local", "localhost"]

    public static func isValidTLD(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 253, s == s.lowercased(),
              !s.hasPrefix("."), !s.hasSuffix(".") else { return false }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/"))
        guard s.unicodeScalars.allSatisfy({ $0.isASCII && !forbidden.contains($0) }) else { return false }
        let labels = s.split(separator: ".", omittingEmptySubsequences: false)
        guard let last = labels.last, !reservedTLDs.contains(String(last)) else { return false }
        let label = #"^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"#
        return labels.allSatisfy { $0.range(of: label, options: .regularExpression) != nil }
    }

    public static func validatedTLD(_ tld: String) throws -> String {
        guard isValidTLD(tld) else { throw InvalidTLD(tld) }
        return tld
    }

    // Written by the root helper, so re-check the standardized parent is exactly /etc/resolver.
    // A traversal slipped past isValidTLD would otherwise land a root-owned file anywhere.
    public static func resolverPathChecked(for tld: String) throws -> String {
        let path = try resolverPath(for: validatedTLD(tld))
        let parent = URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent().path
        guard parent == "/etc/resolver" else { throw InvalidTLD(tld) }
        return path
    }

    public static let supportDir = "/Library/Application Support/KTStack"
    public static var dnsmasqBinaryPath: String {
        "\(supportDir)/bin/dnsmasq"
    }

    public static var dnsmasqConfPath: String {
        "\(supportDir)/dnsmasq.conf"
    }

    public static var dnsmasqLogPath: String {
        "\(supportDir)/dnsmasq.log"
    }

    public static let daemonLabel = "com.ktstack.dnsmasq"
    public static var daemonPlistPath: String {
        "/Library/LaunchDaemons/\(daemonLabel).plist"
    }

    public static let dnsPort = 53

    public static var resolverContents: String {
        "nameserver 127.0.0.1\nport \(dnsPort)\n"
    }

    public static func dnsmasqConf(for tld: String) -> String {
        """
        port=\(dnsPort)
        listen-address=127.0.0.1
        bind-interfaces
        no-resolv
        no-hosts
        address=/.\(tld)/127.0.0.1
        """
    }

    public static var daemonPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(daemonLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(dnsmasqBinaryPath)</string>
                <string>-k</string>
                <string>--conf-file=\(dnsmasqConfPath)</string>
            </array>
            <key>RunAtLoad</key><true/>
            <key>KeepAlive</key><true/>
            <key>StandardErrorPath</key><string>\(dnsmasqLogPath)</string>
            <key>StandardOutPath</key><string>\(dnsmasqLogPath)</string>
        </dict>
        </plist>
        """
    }
}
