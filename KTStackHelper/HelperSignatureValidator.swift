import Foundation
import Security

enum HelperSignatureValidator {
    @objc
    private protocol AuditTokenProvider {
        var auditToken: audit_token_t { get }
    }

    static func isTrustedClient(_ connection: NSXPCConnection) -> Bool {
        guard HelperIdentity.hasSigningIdentity else { return false } // dev build: trust nobody
        guard let requirement = makeRequirement(HelperIdentity.clientRequirement) else { return false }

        var token = unsafeBitCast(connection, to: AuditTokenProvider.self).auditToken
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size) as CFData

        var code: SecCode?
        let copyStatus = SecCodeCopyGuestWithAttributes(
            nil, [kSecGuestAttributeAudit: tokenData] as CFDictionary, [], &code
        )
        guard copyStatus == errSecSuccess, let code else { return false }

        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private static func makeRequirement(_ string: String) -> SecRequirement? {
        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(string as CFString, [], &requirement)
        return status == errSecSuccess ? requirement : nil
    }
}
