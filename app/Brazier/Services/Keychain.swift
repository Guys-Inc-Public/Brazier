import Foundation
import Security

/// Generic-password items under one service, readable after first unlock so a
/// notification action can reach a token while the phone is locked.
enum Keychain {
    private static let service = "org.guysinc.brazier"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain refused the write (\(status)): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
        }
    }

    /// Writes, or throws with the OSStatus. An unsigned build (no entitlements) is the usual cause.
    static func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { _, new in new }
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum SecretKey {
    static func refreshToken(_ id: UUID) -> String { "server.\(id.uuidString).refresh" }
    static func idToken(_ id: UUID) -> String { "server.\(id.uuidString).id" }
    static func apiToken(_ id: UUID) -> String { "server.\(id.uuidString).token" }
    static func sessionCookie(_ id: UUID) -> String { "server.\(id.uuidString).session" }
    static func sessionExpiry(_ id: UUID) -> String { "server.\(id.uuidString).session-expiry" }

    static func all(_ id: UUID) -> [String] {
        [refreshToken(id), idToken(id), apiToken(id), sessionCookie(id), sessionExpiry(id)]
    }
}
