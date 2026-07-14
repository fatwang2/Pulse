import Foundation
import CryptoKit

/// User-supplied Longbridge OpenAPI credentials (legacy API-key mode:
/// App Key / App Secret / Access Token from the developer center).
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

/// Signed HTTP access to the Longbridge OpenAPI gateway. Pulse only needs it to
/// exchange credentials for a socket OTP; quote data itself flows over the socket.
struct LongbridgeHTTP: Sendable {
    var host = URL(string: "https://openapi.longbridge.com")!
    var credentials: LongbridgeCredentials
    var session: URLSession

    init(credentials: LongbridgeCredentials, session: URLSession? = nil) {
        self.credentials = credentials
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            self.session = URLSession(configuration: config)
        }
    }

    /// GET /v1/socket/token — one-time password for authenticating the quote socket.
    func fetchSocketOTP() async throws -> String {
        let data = try await get(path: "/v1/socket/token")
        struct Envelope: Decodable {
            struct Payload: Decodable { var otp: String }
            var code: Int
            var message: String?
            var data: Payload?
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.code == 0, let otp = envelope.data?.otp else {
            throw LongbridgeError.api(code: envelope.code, message: envelope.message ?? "unknown error")
        }
        return otp
    }

    private func get(path: String, query: String = "") async throws -> Data {
        var components = URLComponents(url: host, resolvingAgainstBaseURL: false)!
        components.path = path
        if !query.isEmpty { components.percentEncodedQuery = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"

        let timestamp = String(Int(Date.now.timeIntervalSince1970))
        request.setValue(credentials.appKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(credentials.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.signature(
            method: "GET", path: path, query: query,
            credentials: credentials, timestamp: timestamp, body: nil
        ), forHTTPHeaderField: "X-Api-Signature")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.network(underlying: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.badResponse("non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300: return data
        case 429: throw ProviderError.rateLimited
        case 400..<500: throw ProviderError.clientError(status: http.statusCode,
                                                        detail: "HTTP \(http.statusCode) from Longbridge")
        default: throw ProviderError.badResponse("HTTP \(http.statusCode) from Longbridge")
        }
    }

    /// Request signature, byte-for-byte compatible with the official SDK implementation
    /// (openapi/rust/crates/httpclient/src/signature.rs):
    ///   canonical = "{method}|{path}|{query}|{signed header values}|{signed header names}|" + sha1hex(body)?
    ///   signature = hex(hmacSHA256("HMAC-SHA256|" + sha1hex(canonical), appSecret))
    static func signature(method: String, path: String, query: String,
                          credentials: LongbridgeCredentials, timestamp: String, body: Data?) -> String {
        let signedHeaders = "authorization;x-api-key;x-timestamp"
        let signedValues = "authorization:\(credentials.accessToken)\nx-api-key:\(credentials.appKey)\nx-timestamp:\(timestamp)\n"

        var canonical = "\(method)|\(path)|\(query)|\(signedValues)|\(signedHeaders)|"
        if let body, !body.isEmpty {
            canonical += sha1Hex(body)
        }

        let stringToSign = "HMAC-SHA256|" + sha1Hex(Data(canonical.utf8))
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: SymmetricKey(data: Data(credentials.appSecret.utf8))
        )
        let hex = mac.map { String(format: "%02x", $0) }.joined()
        return "HMAC-SHA256 SignedHeaders=\(signedHeaders), Signature=\(hex)"
    }

    private static func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// How the Longbridge provider authenticates: user-pasted developer-center credentials, or
/// OAuth tokens from the browser authorization flow.
public enum LongbridgeAuth: Sendable {
    case apiKey(LongbridgeCredentials)
    case oauth(LongbridgeOAuthSession)
}

public enum LongbridgeError: Error, Sendable {
    /// Business error from the OpenAPI gateway (non-zero code)
    case api(code: Int, message: String)
    /// Socket-level auth or transport failure
    case socket(String)
    /// Credentials missing — the provider is registered but not configured yet
    case notConfigured
}
