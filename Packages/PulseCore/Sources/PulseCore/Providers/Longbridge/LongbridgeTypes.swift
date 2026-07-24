/// User-supplied Longbridge OpenAPI credentials. The official SDK supports this
/// API-key mode in addition to the preferred OAuth flow.
public struct LongbridgeCredentials: Codable, Sendable, Hashable {
    public var appKey: String
    public var appSecret: String
    public var accessToken: String

    public init(appKey: String, appSecret: String, accessToken: String) {
        self.appKey = appKey
        self.appSecret = appSecret
        self.accessToken = accessToken
    }

    public var isComplete: Bool {
        !appKey.isEmpty && !appSecret.isEmpty && !accessToken.isEmpty
    }
}

/// How the official Longbridge SDK authenticates.
public enum LongbridgeAuth: Sendable {
    case apiKey(LongbridgeCredentials)
    case oauth(LongbridgeOAuthSession)
}

public enum LongbridgeError: Error, Sendable {
    /// Business error returned by Longbridge OpenAPI.
    case api(code: Int, message: String)
    /// Official SDK loading, authentication, or transport failure.
    case socket(String)
    /// Credentials missing — the provider is registered but not configured yet.
    case notConfigured
}

public enum LongbridgeConnectionIssue: Sendable, Equatable {
    case connectionLimit
    case authentication
    case rateLimited
    case network
    case server
}

public enum LongbridgeConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case reconnecting
    case connected
    case failed(LongbridgeConnectionIssue)
}
