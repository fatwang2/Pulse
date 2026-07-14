import Foundation
import Security

/// Keychain persistence for the user's Longbridge OpenAPI secrets — legacy API-key
/// credentials and OAuth tokens live under separate accounts. Both can trade the user's
/// account, so neither ever touches UserDefaults.
public enum LongbridgeCredentialStore {
    private static let service = "app.pulse.longbridge"
    private static let apiKeyAccount = "openapi-credentials"
    private static let oauthAccount = "oauth-tokens"

    // MARK: - Legacy API-key credentials

    public static func load() -> LongbridgeCredentials? {
        loadValue(account: apiKeyAccount)
    }

    public static func save(_ credentials: LongbridgeCredentials) throws {
        try saveValue(credentials, account: apiKeyAccount)
    }

    public static func clear() {
        SecItemDelete(baseQuery(account: apiKeyAccount) as CFDictionary)
    }

    // MARK: - OAuth tokens

    public static func loadOAuthTokens() -> LongbridgeOAuthTokens? {
        loadValue(account: oauthAccount)
    }

    public static func saveOAuthTokens(_ tokens: LongbridgeOAuthTokens) throws {
        try saveValue(tokens, account: oauthAccount)
    }

    public static func clearOAuthTokens() {
        SecItemDelete(baseQuery(account: oauthAccount) as CFDictionary)
    }

    // MARK: - Keychain plumbing

    private static func loadValue<Value: Decodable>(account: String) -> Value? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func saveValue(_ value: some Encodable, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw LongbridgeError.socket("keychain add failed (\(addStatus))")
            }
        } else if updateStatus != errSecSuccess {
            throw LongbridgeError.socket("keychain update failed (\(updateStatus))")
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
