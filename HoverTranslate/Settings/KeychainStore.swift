import Foundation
import Security

/// The narrow Keychain surface this app needs.
protocol SecretStoring: Sendable {
    func secret(for account: String) -> String?
    func setSecret(_ value: String?, for account: String) throws
}

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Stores exactly one item per account, in a service namespace that belongs to
/// this app. It never enumerates or reads other applications' items.
///
/// The API key lives here and nowhere else: not in UserDefaults, not in source,
/// not in logs. `testConnection` uses a synthetic key, never a real one.
struct KeychainStore: SecretStoring {
    static let service = "com.atat.HoverTranslate"
    static let deepSeekAPIKeyAccount = "deepseek-api-key"

    let service: String
    let accessGroup: String?

    init(service: String = KeychainStore.service, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func secret(for account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    func setSecret(_ value: String?, for account: String) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            try deleteSecret(for: account)
            return
        }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var update = base
        update[kSecValueData as String] = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }

        var insert = base
        insert[kSecValueData as String] = Data(trimmed.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if let accessGroup {
            insert[kSecAttrAccessGroup as String] = accessGroup
        }
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
    }

    func deleteSecret(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // Deleting an item that is not there is the state the caller asked for.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
