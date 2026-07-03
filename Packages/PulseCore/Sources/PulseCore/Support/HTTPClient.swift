import Foundation

/// Lightweight HTTP wrapper: unified User-Agent, timeout, and error semantics.
public struct HTTPClient: Sendable {
    public var session: URLSession
    public var defaultHeaders: [String: String]

    public static let defaultUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    public init(session: URLSession? = nil, defaultHeaders: [String: String] = [:]) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.httpAdditionalHeaders = nil
            self.session = URLSession(configuration: config)
        }
        self.defaultHeaders = defaultHeaders
    }

    public func get(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in defaultHeaders { request.setValue(v, forHTTPHeaderField: k) }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

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
                                                        detail: "HTTP \(http.statusCode) for \(url.host ?? "?")")
        default: throw ProviderError.badResponse("HTTP \(http.statusCode) for \(url.host ?? "?")")
        }
    }
}
