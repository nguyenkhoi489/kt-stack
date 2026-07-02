import Foundation
import Security

enum RootCAConstraintError: Error, Equatable {
    case notSingleCertificate
    case unparseable
    case notSelfSigned
    case notCertificateAuthority
    case organizationMismatch

    var message: String {
        switch self {
        case .notSingleCertificate: "Expected exactly one PEM certificate."
        case .unparseable: "Certificate could not be parsed."
        case .notSelfSigned: "Certificate is not self-signed."
        case .notCertificateAuthority: "Certificate is not a certificate authority."
        case .organizationMismatch: "Certificate is not the KTStack local CA."
        }
    }
}

enum RootCAConstraint {
    // mkcert bakes this org name into every CA it generates, so this is the match value for our own
    // CA, not a placeholder. Changing it rejects the real cert.
    static let expectedOrganization = "mkcert development CA"

    static func validateKTStackRootCA(pemData: Data) -> RootCAConstraintError? {
        guard certificateBlockCount(pemData) == 1, let der = pemToDER(pemData) else {
            return .notSingleCertificate
        }
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            return .unparseable
        }
        guard isSelfSigned(certificate) else { return .notSelfSigned }
        guard isCertificateAuthority(certificate) else { return .notCertificateAuthority }
        guard subjectOrganization(certificate) == expectedOrganization else {
            return .organizationMismatch
        }
        return nil
    }

    static func pemToDER(_ pem: Data) -> Data? {
        guard let text = String(data: pem, encoding: .utf8) else { return nil }
        var base64 = "", inside = false
        for line in text.split(separator: "\n") {
            if line.contains("BEGIN CERTIFICATE") { inside = true; continue }
            if line.contains("END CERTIFICATE") { break }
            if inside { base64 += line.trimmingCharacters(in: .whitespaces) }
        }
        return Data(base64Encoded: base64)
    }

    private static func certificateBlockCount(_ pem: Data) -> Int {
        guard let text = String(data: pem, encoding: .utf8) else { return 0 }
        return text.components(separatedBy: "BEGIN CERTIFICATE").count - 1
    }

    private static func isSelfSigned(_ certificate: SecCertificate) -> Bool {
        guard let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate),
              let subject = SecCertificateCopyNormalizedSubjectSequence(certificate) else { return false }
        return CFEqual(issuer, subject)
    }

    private static func isCertificateAuthority(_ certificate: SecCertificate) -> Bool {
        guard let properties = subjectProperties(certificate, oid: kSecOIDBasicConstraints) else { return false }
        for entry in properties where (entry[kSecPropertyKeyLabel] as? String) == "Certificate Authority" {
            if let flag = entry[kSecPropertyKeyValue] as? String {
                return flag.caseInsensitiveCompare("yes") == .orderedSame || flag == "1"
            }
            if let flag = entry[kSecPropertyKeyValue] as? Bool { return flag }
        }
        return false
    }

    private static func subjectOrganization(_ certificate: SecCertificate) -> String? {
        guard let properties = subjectProperties(certificate, oid: kSecOIDX509V1SubjectName) else { return nil }
        let organizationOID = kSecOIDOrganizationName as String
        for entry in properties where (entry[kSecPropertyKeyLabel] as? String) == organizationOID {
            if let value = entry[kSecPropertyKeyValue] as? String { return value }
        }
        return nil
    }

    private static func subjectProperties(_ certificate: SecCertificate, oid: CFString) -> [[CFString: Any]]? {
        guard let values = SecCertificateCopyValues(certificate, [oid] as CFArray, nil) as? [CFString: Any],
              let section = values[oid] as? [CFString: Any],
              let entries = section[kSecPropertyKeyValue] as? [[CFString: Any]] else { return nil }
        return entries
    }
}
