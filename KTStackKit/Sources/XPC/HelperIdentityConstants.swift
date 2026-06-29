import Foundation
import Security

public enum HelperIdentity {
    public static let machServiceName = "com.ktstack.helper"
    public static let helperBundleID = "com.ktstack.helper"
    public static let appBundleID = "com.ktstack.app"

    public static var hasSigningIdentity: Bool {
        resolvedTeamID() != nil
    }

    public static var clientRequirement: String {
        requirement(for: appBundleID, team: resolvedTeamID())
    }

    public static var helperRequirement: String {
        requirement(for: helperBundleID, team: resolvedTeamID())
    }

    public static func resolvedTeamID() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return nil }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }

        var developerIDRequirement: SecRequirement?
        let anchor = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecRequirementCreateWithString(anchor as CFString, [], &developerIDRequirement) == errSecSuccess,
              let developerIDRequirement,
              SecStaticCodeCheckValidity(staticCode, [], developerIDRequirement) == errSecSuccess else { return nil }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String else { return nil }

        return normalizedTeam(team)
    }

    static func requirement(for identifier: String, team: String?) -> String {
        if let strong = strongRequirement(for: identifier, team: team) { return strong }
        #if DEBUG
            return "identifier \"\(identifier)\""
        #else
            return unsatisfiableRequirement
        #endif
    }

    static func strongRequirement(for identifier: String, team: String?) -> String? {
        guard let team = normalizedTeam(team) else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" "
            + "and certificate leaf[subject.OU] = \"\(team)\""
    }

    static func normalizedTeam(_ team: String?) -> String? {
        guard let trimmed = team?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static let unsatisfiableRequirement = "cdhash H\"0000000000000000000000000000000000000000\""
}
