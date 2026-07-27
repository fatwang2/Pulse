import Foundation

enum LongbridgeEndpointSelection {
    static let globalHTTPBaseURL = URL(string: "https://openapi.longbridge.com")!
    static let chinaHTTPBaseURL = URL(string: "https://openapi.longbridge.cn")!
    static let globalQuoteWebSocketURL = URL(string: "wss://openapi-quote.longbridge.com/v2")!
    static let chinaQuoteWebSocketURL = URL(string: "wss://openapi-quote.longbridge.cn/v2")!

    /// The global access point is the safe default for a public app: Longbridge
    /// accounts can belong to different data centers regardless of where the Mac
    /// happens to be. The China endpoint remains an explicit transport override
    /// for diagnostics and managed deployments; it never changes OAuth identity.
    static func usesChinaEndpoint(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        localeRegion: String? = Locale.current.region?.identifier
    ) -> Bool {
        _ = timeZoneIdentifier
        _ = localeRegion
        if let explicit = environment["LONGBRIDGE_REGION"]
            ?? environment["LONGPORT_REGION"] {
            return explicit.caseInsensitiveCompare("CN") == .orderedSame
        }
        return false
    }

    static func httpBaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        localeRegion: String? = Locale.current.region?.identifier
    ) -> URL {
        let usesChina = usesChinaEndpoint(
            environment: environment,
            timeZoneIdentifier: timeZoneIdentifier,
            localeRegion: localeRegion
        )
        return usesChina ? chinaHTTPBaseURL : globalHTTPBaseURL
    }

    static func quoteWebSocketURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        localeRegion: String? = Locale.current.region?.identifier
    ) -> URL {
        let usesChina = usesChinaEndpoint(
            environment: environment,
            timeZoneIdentifier: timeZoneIdentifier,
            localeRegion: localeRegion
        )
        return usesChina ? chinaQuoteWebSocketURL : globalQuoteWebSocketURL
    }
}
