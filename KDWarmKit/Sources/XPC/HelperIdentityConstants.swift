import Foundation

/// Single source of truth for the app/helper identities and the code-signing requirements used
/// for XPC peer validation. Referenced by BOTH the app (client) and the helper (listener) so the
/// signature check can never drift between two string literals — and so it keeps passing after a
/// Sparkle-re-signed release replaces the app (Phase 9 re-validates this).
public enum HelperIdentity {
    public static let machServiceName = "com.kdwarm.helper"
    public static let helperBundleID  = "com.kdwarm.helper"
    public static let appBundleID     = "com.kdwarm.app"

    /// Apple Developer Team ID. EMPTY on the dev/ad-hoc build (no Developer ID configured yet);
    /// Phase 9 fills it when signing is set up. While empty, the live SMAppService daemon + the
    /// Team-ID-pinned XPC check cannot be exercised — that path is intentionally deferred.
    ///
    /// ⚠️ SECURITY GO-LIVE GATE: setting a non-empty Team ID activates the LIVE root helper (it then
    /// writes /etc/resolver/*, installs a System-Keychain trust root, controls a root launchd daemon).
    /// Some privileged-surface hardening was deliberately deferred while this is empty. BEFORE setting
    /// it for production, complete the gate documented in `HelperCAManager` (class doc): constrain
    /// `installRootCA` to KTStack's own CA, decide on an Authorization Services consent gate for
    /// system-trust ops, enforce Developer-ID + notarization in CI, and re-verify the TLD-validation
    /// invariants through a REAL XPC/sudo path (they are currently only Kit-layer tested).
    public static let teamID = ""

    /// True once a real signing identity (Team ID) exists — gates the live privileged path.
    public static var hasSigningIdentity: Bool { !teamID.isEmpty }

    /// The requirement the HELPER enforces on an incoming app connection.
    /// Release (Team ID set): pin Apple anchor + app identifier + leaf Org-Unit = Team ID.
    /// Dev (no Team ID): identifier-only — deliberately NOT trusted for live root actions; the
    /// helper refuses to perform privileged work until `hasSigningIdentity` is true.
    public static var clientRequirement: String { requirement(for: appBundleID) }

    /// The requirement the APP pins on the helper connection (mirror of the above).
    public static var helperRequirement: String { requirement(for: helperBundleID) }

    private static func requirement(for identifier: String) -> String {
        teamID.isEmpty
            ? "identifier \"\(identifier)\""
            : "anchor apple generic and identifier \"\(identifier)\" "
              + "and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
