import Foundation

enum RestoreNaming {
    static func label(from siteName: String) -> String {
        let lowered = siteName.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lowered.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "site" : trimmed
    }

    static func databaseBase(from label: String) -> String {
        var result = ""
        for scalar in label.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") || scalar == "_" {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }
        let collapsed = result.replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "site" : trimmed
    }

    static func uniqueName(
        base: String,
        separator: String = "_",
        exists: (String) async throws -> Bool
    ) async throws -> String {
        if try await !exists(base) { return base }
        var suffix = 2
        while true {
            let candidate = "\(base)\(separator)\(suffix)"
            if try await !exists(candidate) { return candidate }
            suffix += 1
        }
    }
}
