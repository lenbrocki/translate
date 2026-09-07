import Foundation
import Security

/// API keys live in the login keychain rather than in a preferences file, so
/// they are encrypted at rest and never show up in a plist someone might back
/// up or screenshot. One item per provider, so switching provider doesn't make
/// you paste a key again.
enum Keychain {
    private static let service = "com.lennartbrocki.translate"

    static func readAPIKey(for provider: Provider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Replaces any existing item rather than updating it in place.
    ///
    /// `SecItemUpdate` needs permission for an item some other binary created,
    /// which is exactly what raises the password prompt. Deleting and re-adding
    /// does not, and it leaves the running build as the item's owner, so its
    /// later reads go through without asking again. That matters here because
    /// an ad-hoc signature changes with every build, making each build a
    /// different application as far as the keychain is concerned.
    @discardableResult
    static func writeAPIKey(_ key: String, for provider: Provider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteAPIKey(for: provider) }

        SecItemDelete(baseQuery(provider) as CFDictionary)

        var insert = baseQuery(provider)
        insert[kSecValueData as String] = Data(trimmed.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteAPIKey(for provider: Provider) -> Bool {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(_ provider: Provider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
    }
}
