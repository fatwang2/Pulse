import Foundation
import Security

/// Keychain persistence for per-provider BYOK credentials, one generic-password item
/// per provider id. Longbridge keeps its dedicated store because of OAuth token
/// rotation; every newer key-based source (Fuyao onward) stores its fields here.
/// Credentials grant access to the user's paid data quota, so they never touch
/// UserDefaults.
public enum ProviderCredentialStore {
    public struct KeychainFailure: Error, Sendable {
        public let status: OSStatus
    }

    private static let baseService = "app.pulse.providers"

    /// Debug and release builds must never silently consume each other's secrets.
    private static var service: String {
        switch Bundle.main.bundleIdentifier {
        case "app.pulse.mac", "app.pulse.ios": "\(baseService).release"
        case "app.pulse.mac.dev", "app.pulse.ios.dev": "\(baseService).debug"
        default: baseService
        }
    }

    public static func load(providerID: String) -> [String: String]? {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    public static func save(_ credentials: [String: String], providerID: String) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = baseQuery(providerID: providerID)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainFailure(status: addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainFailure(status: updateStatus)
        }
    }

    public static func clear(providerID: String) {
        SecItemDelete(baseQuery(providerID: providerID) as CFDictionary)
    }

    private static func baseQuery(providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "\(providerID)-credentials",
        ]
    }
}
