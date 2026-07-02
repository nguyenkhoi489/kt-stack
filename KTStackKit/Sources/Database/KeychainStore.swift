import Foundation
import Security

public struct KeychainStore: Sendable {
    // ThisDeviceOnly and non-synchronizable keep DB passwords out of iCloud Keychain and off other
    // devices; flipping either would sync local dev credentials to the cloud.
    public static let accessibleAttr = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    public static let synchronizable = false

    private let service: String

    public init(service: String = "com.ktstack.db") {
        self.service = service
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: Self.synchronizable,
        ]
    }

    public func set(_ password: String, account: String) throws {
        let data = Data(password.utf8)
        let query = baseQuery(account: account)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw keychainError(updateStatus, "update password")
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = Self.accessibleAttr
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(addStatus, "add password")
        }
    }

    public func get(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(decoding: data, as: UTF8.self)
        case errSecItemNotFound:
            return nil
        default:
            throw keychainError(status, "read password")
        }
    }

    public func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status, "delete password")
        }
    }

    public static func migrateService(from oldService: String, to newService: String) {
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: oldService,
            kSecAttrSynchronizable as String: synchronizable,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(listQuery as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }

        let source = KeychainStore(service: oldService)
        let destination = KeychainStore(service: newService)
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let password = (try? source.get(account: account)) ?? nil else { continue }
            try? destination.set(password, account: account)
            try? source.delete(account: account)
        }
    }

    private func keychainError(_ status: OSStatus, _ action: String) -> DatabaseError {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return .connection("Keychain \(action) failed: \(detail)")
    }
}
