import Foundation
import CryptoKit

/// OAuth 2.0 tokens for the Longbridge OpenAPI gateway. Refresh tokens rotate on every
/// refresh, so whatever is persisted must be replaced immediately after each refresh —
/// a stale refresh token is permanently dead.
public struct LongbridgeOAuthTokens: Codable, Sendable, Hashable {
    public var clientID: String
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(clientID: String, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.clientID = clientID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Cached dynamic client registration (client id is not a secret; the redirect URIs are
/// derived from the bundle id and loopback port, so dev and release builds register
/// separate clients).
struct LongbridgeOAuthClient: Codable, Sendable {
    var clientID: String
    var scope: String
    var redirectURIs: [String]
    var logoURI: String?
}

/// Browser-based authorization: dynamic client registration → authorize URL with PKCE →
/// redirect back into the app → code/token exchange. The redirect prefers a one-shot
/// loopback HTTP endpoint (proper success page in the tab, no "open app?" prompt) and
/// falls back to the custom URL scheme when the port can't be bound; scheme callbacks are
/// fed in via `handleCallback`.
public actor LongbridgeOAuthAuthenticator {
    public static let host = URL(string: "https://openapi.longbridge.com")!
    static let loopbackPort: UInt16 = 41917
    static let callbackPath = "/oauth/callback"
    /// Shown by the authorize page next to the client name (RFC 7591 `logo_uri`).
    static let logoURI = "https://pulse-market-glance.wangding0798.chatgpt.site/pulse-icon.png"
    static var loopbackRedirectURI: String { "http://localhost:\(loopbackPort)\(callbackPath)" }
    private static let clientCacheKey = "pulse.longbridge.oauthClient.v1"

    private let schemeRedirectURI: String
    private let clientName: String
    private let defaults: UserDefaults
    private var pending: PendingAuthorization?

    private struct PendingAuthorization {
        var state: String
        var continuation: CheckedContinuation<URL, any Error>
    }

    public init(redirectScheme: String, clientName: String, defaults: UserDefaults = .standard) {
        self.schemeRedirectURI = "\(redirectScheme)://oauth/callback"
        self.clientName = clientName
        self.defaults = defaults
    }

    // MARK: - Authorization flow

    /// Runs the full browser authorization. `openURL` is called with the authorize page;
    /// the flow completes when the browser redirects back, or fails after 5 minutes.
    public func authorize(openURL: @Sendable @escaping (URL) -> Void) async throws -> LongbridgeOAuthTokens {
        let client = try await ensureClient()

        var server: LongbridgeLoopbackServer? = LongbridgeLoopbackServer(
            port: Self.loopbackPort,
            callbackPath: Self.callbackPath
        ) { [weak self] url in
            guard let self else { return }
            Task { _ = await self.handleCallback(url) }
        }
        let redirectURI: String
        do {
            try await server?.start()
            redirectURI = Self.loopbackRedirectURI
        } catch {
            server = nil
            redirectURI = schemeRedirectURI
        }

        do {
            let tokens = try await runAuthorization(client: client, redirectURI: redirectURI, openURL: openURL)
            await server?.stop()
            return tokens
        } catch {
            await server?.stop()
            throw error
        }
    }

    private func runAuthorization(client: LongbridgeOAuthClient, redirectURI: String,
                                  openURL: @Sendable @escaping (URL) -> Void) async throws -> LongbridgeOAuthTokens {
        let verifier = Self.randomURLSafe(32)
        let state = Self.randomURLSafe(16)

        var components = URLComponents(url: Self.host.appending(path: "/oauth2/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: client.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: client.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.pkceChallenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        let authorizeURL = components.url!

        pending?.continuation.resume(throwing: CancellationError())
        pending = nil

        let timeout = Task {
            try? await Task.sleep(for: .seconds(300))
            self.expirePending(state: state)
        }
        defer { timeout.cancel() }

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            pending = PendingAuthorization(state: state, continuation: continuation)
            openURL(authorizeURL)
        }

        guard let code = Self.queryValue("code", in: callback) else {
            throw LongbridgeError.socket("authorization callback carried no code")
        }
        return try await Self.exchangeToken(clientID: client.clientID, form: [
            "grant_type": "authorization_code",
            "client_id": client.clientID,
            "redirect_uri": redirectURI,
            "code": code,
            "code_verifier": verifier,
        ])
    }

    /// Feed a `scheme://oauth/callback?...` URL from the system open-URL handler.
    /// Returns whether the URL belonged to an in-flight authorization.
    public func handleCallback(_ url: URL) -> Bool {
        guard let pending, Self.queryValue("state", in: url) == pending.state else { return false }
        self.pending = nil
        pending.continuation.resume(returning: url)
        return true
    }

    private func expirePending(state: String) {
        guard let pending, pending.state == state else { return }
        self.pending = nil
        pending.continuation.resume(throwing: ProviderError.network(underlying: "authorization timed out"))
    }

    // MARK: - Dynamic client registration

    private var desiredRedirectURIs: [String] {
        [Self.loopbackRedirectURI, schemeRedirectURI]
    }

    private func ensureClient() async throws -> LongbridgeOAuthClient {
        if let cached = LongbridgeCredentialStore.loadOAuthClient(),
           Set(cached.redirectURIs) == Set(desiredRedirectURIs) {
            return cached
        }
        if let data = defaults.data(forKey: Self.clientCacheKey),
           let cached = try? JSONDecoder().decode(LongbridgeOAuthClient.self, from: data),
           Set(cached.redirectURIs) == Set(desiredRedirectURIs) {
            try? LongbridgeCredentialStore.saveOAuthClient(cached)
            return cached
        }

        var request = URLRequest(url: Self.host.appending(path: "/oauth2/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Registration(
            clientName: clientName,
            redirectURIs: desiredRedirectURIs,
            logoURI: Self.logoURI
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 || (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LongbridgeError.socket("OAuth client registration failed")
        }
        struct Registered: Decodable {
            let clientID: String
            let scope: String?
            enum CodingKeys: String, CodingKey {
                case clientID = "client_id"
                case scope
            }
        }
        let registered = try JSONDecoder().decode(Registered.self, from: data)
        let client = LongbridgeOAuthClient(
            clientID: registered.clientID,
            scope: registered.scope ?? "",
            redirectURIs: desiredRedirectURIs,
            logoURI: Self.logoURI
        )
        try LongbridgeCredentialStore.saveOAuthClient(client)
        defaults.set(try JSONEncoder().encode(client), forKey: Self.clientCacheKey)
        return client
    }

    private struct Registration: Encodable {
        var clientName: String
        var redirectURIs: [String]
        var logoURI: String
        var grantTypes = ["authorization_code", "refresh_token"]
        var responseTypes = ["code"]
        var tokenEndpointAuthMethod = "none"

        enum CodingKeys: String, CodingKey {
            case clientName = "client_name"
            case redirectURIs = "redirect_uris"
            case logoURI = "logo_uri"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        }
    }

    // MARK: - Token endpoint

    static func exchangeToken(clientID: String, form: [String: String]) async throws -> LongbridgeOAuthTokens {
        var request = URLRequest(url: host.appending(path: "/oauth2/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProviderError.network(underlying: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw LongbridgeError.socket("token endpoint failed: \(detail)")
        }
        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Double?
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return LongbridgeOAuthTokens(
            clientID: clientID,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? form["refresh_token"] ?? "",
            expiresAt: Date.now.addingTimeInterval(token.expiresIn ?? 3600)
        )
    }

    public static func refresh(_ tokens: LongbridgeOAuthTokens) async throws -> LongbridgeOAuthTokens {
        try await exchangeToken(clientID: tokens.clientID, form: [
            "grant_type": "refresh_token",
            "client_id": tokens.clientID,
            "refresh_token": tokens.refreshToken,
        ])
    }

    // MARK: - PKCE helpers

    static func pkceChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}

/// Owns live OAuth tokens for the quote connection: refreshes ahead of expiry and pushes
/// every rotation to the persistence hook before use, then mints socket OTPs with the
/// fresh bearer.
public actor LongbridgeOAuthSession {
    private var tokens: LongbridgeOAuthTokens
    private let persist: @Sendable (LongbridgeOAuthTokens) -> Void

    public init(tokens: LongbridgeOAuthTokens, persist: @escaping @Sendable (LongbridgeOAuthTokens) -> Void) {
        self.tokens = tokens
        self.persist = persist
    }

    public func fetchSocketOTP() async throws -> String {
        let bearer = try await freshAccessToken()
        var request = URLRequest(url: LongbridgeOAuthAuthenticator.host.appending(path: "/v1/socket/token"))
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProviderError.network(underlying: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderError.badResponse("OTP request failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        struct Envelope: Decodable {
            struct Payload: Decodable { var otp: String }
            var code: Int
            var data: Payload?
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.code == 0, let otp = envelope.data?.otp else {
            throw LongbridgeError.api(code: envelope.code, message: "socket token rejected")
        }
        return otp
    }

    private func freshAccessToken() async throws -> String {
        if tokens.expiresAt.timeIntervalSinceNow > 60 {
            return tokens.accessToken
        }
        let refreshed = try await LongbridgeOAuthAuthenticator.refresh(tokens)
        tokens = refreshed
        persist(refreshed)
        return refreshed.accessToken
    }
}
