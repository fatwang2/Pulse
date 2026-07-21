import Foundation
import Security

/// Keychain persistence for the user's Longbridge OpenAPI secrets — legacy API-key
/// credentials and OAuth tokens live under separate accounts. Both can trade the user's
/// account, so neither ever touches UserDefaults.
public enum LongbridgeCredentialStore {
    private static let legacyService = "app.pulse.longbridge"
    private static let apiKeyAccount = "openapi-credentials"
    private static let oauthAccount = "oauth-tokens"
    private static let oauthClientAccount = "oauth-client-registration"

    /// Debug and release builds must never silently consume each other's OAuth tokens.
    /// The production build alone imports the former shared item once so existing users
    /// keep their authorization after upgrading.
    private static var service: String {
        switch Bundle.main.bundleIdentifier {
        case "app.pulse.mac": "\(legacyService).release"
        case "app.pulse.mac.dev": "\(legacyService).debug"
        default: legacyService
        }
    }

    private static var migratesLegacyService: Bool {
        Bundle.main.bundleIdentifier == "app.pulse.mac"
    }

    // MARK: - Legacy API-key credentials

    public static func load() -> LongbridgeCredentials? {
        loadValue(account: apiKeyAccount)
    }

    public static func save(_ credentials: LongbridgeCredentials) throws {
        try saveValue(credentials, account: apiKeyAccount)
    }

    public static func clear() {
        delete(account: apiKeyAccount)
    }

    // MARK: - OAuth tokens

    public static func loadOAuthTokens() -> LongbridgeOAuthTokens? {
        loadValue(account: oauthAccount)
    }

    public static func saveOAuthTokens(_ tokens: LongbridgeOAuthTokens) throws {
        try saveValue(tokens, account: oauthAccount)
    }

    public static func clearOAuthTokens() {
        delete(account: oauthAccount)
    }

    // MARK: - OAuth client registration

    /// Dynamic OAuth registration is not secret, but storing it beside the tokens keeps it
    /// stable across app reinstalls and prevents a new "Pulse (n)" client on every reconnect.
    static func loadOAuthClient() -> LongbridgeOAuthClient? {
        loadValue(account: oauthClientAccount)
    }

    static func saveOAuthClient(_ client: LongbridgeOAuthClient) throws {
        try saveValue(client, account: oauthClientAccount)
    }

    // MARK: - Keychain plumbing

    private static func loadValue<Value: Codable>(account: String) -> Value? {
        if let value: Value = loadValue(account: account, service: service) {
            return value
        }
        guard migratesLegacyService,
              let legacy: Value = loadValue(account: account, service: legacyService) else {
            return nil
        }
        do {
            try saveValue(legacy, account: account, service: service)
            SecItemDelete(baseQuery(account: account, service: legacyService) as CFDictionary)
        } catch {
            // Reading the legacy item is still better than appearing logged out. A later
            // launch can retry the migration if Keychain was temporarily unavailable.
        }
        return legacy
    }

    private static func loadValue<Value: Codable>(account: String, service: String) -> Value? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func saveValue(_ value: some Encodable, account: String) throws {
        try saveValue(value, account: account, service: service)
    }

    private static func saveValue(_ value: some Encodable, account: String, service: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account, service: service)
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

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        if migratesLegacyService {
            SecItemDelete(baseQuery(account: account, service: legacyService) as CFDictionary)
        }
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
