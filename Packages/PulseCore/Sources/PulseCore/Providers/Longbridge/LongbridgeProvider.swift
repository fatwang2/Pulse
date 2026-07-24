#if os(macOS)
import Foundation

/// Longbridge OpenAPI quote source backed exclusively by the official SDK.
///
/// Pulse owns provider routing, symbol mapping, and presentation models. The SDK
/// owns authentication, quote transport, subscriptions, heartbeat, and reconnect.
public actor LongbridgeProvider: QuoteProvider {
    public static let providerID = "longbridge"

    private let sdk: LongbridgeSDKBridge
    private var configured: Bool

    public init(auth: LongbridgeAuth? = nil) {
        let auth = Self.usableAuth(auth)
        self.sdk = LongbridgeSDKBridge(auth: auth)
        self.configured = auth != nil
    }

    /// Swaps the auth mode at runtime and asks the SDK to create a fresh quote
    /// context on the next request.
    public func updateAuth(_ auth: LongbridgeAuth?) async {
        let auth = Self.usableAuth(auth)
        configured = auth != nil
        await sdk.updateAuth(auth)
    }

    public func connectionStatusUpdates() async -> AsyncStream<LongbridgeConnectionStatus> {
        await sdk.statusUpdates()
    }

    public func resetConnection() async {
        await sdk.resetConnection()
    }

    /// Validation hook used by the local SDK self-test.
    public func debugSDKSubscriptionRoundTrip(for symbols: [SymbolID]) async throws {
        guard configured else { throw LongbridgeError.notConfigured }
        try await sdk.subscriptionRoundTrip(for: symbols)
    }

    public nonisolated var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: Self.providerID,
            name: PulseLocalization.localizedString("provider.longbridge"),
            markets: [.us, .hk, .sh, .sz],
            capabilities: [.referenceData, .quotes, .candles, .streaming],
            delay: [.us: 0, .hk: 0, .sh: 0, .sz: 0],
            rateLimit: RateLimitPolicy(minInterval: 0.12, batchSize: 500),
            credentials: [
                CredentialField(key: "appKey", label: "App Key", secure: false),
                CredentialField(key: "appSecret", label: "App Secret"),
                CredentialField(key: "accessToken", label: "Access Token"),
            ],
            // Push carries the liveliness; polling only reconciles and bootstraps.
            suggestedPollInterval: 60,
            overnightMarkets: [.us]
        )
    }

    /// Exercises SDK authentication and one quote request when credentials are saved.
    public func validateConnection() async throws {
        _ = try await quotes(for: [SymbolID(market: .hk, code: "700")])
    }

    public func search(_ query: String) async throws -> [SymbolInfo] {
        throw ProviderError.unsupported(.search)
    }

    public func securityNames(for symbols: [SymbolID]) async throws -> [SecurityName] {
        guard configured else { throw LongbridgeError.notConfigured }
        return try await sdk.securityNames(for: symbols)
    }

    public func quotes(for symbols: [SymbolID]) async throws -> [Quote] {
        guard configured else { throw LongbridgeError.notConfigured }
        return try await sdk.quotes(for: symbols)
    }

    public func candles(for symbol: SymbolID, period: CandlePeriod, count: Int) async throws -> [Candle] {
        guard configured else { throw LongbridgeError.notConfigured }
        return try await sdk.candles(for: symbol, period: period, count: count)
    }

    public nonisolated func quoteStream(
        for symbols: [SymbolID]
    ) -> AsyncThrowingStream<Quote, any Error>? {
        sdk.quoteStream(for: symbols)
    }

    /// Pulse `SymbolID` → Longbridge `ticker.region`. Crypto is not covered by the
    /// OpenAPI quote packages, so it stays with the other providers.
    static func longbridgeSymbol(for symbol: SymbolID) -> String? {
        if let index = symbol.indexID {
            return switch index {
            case .sp500: ".SPX.US"
            case .nasdaqComposite: ".IXIC.US"
            case .dowJonesIndustrial: ".DJI.US"
            case .nasdaq100: ".NDX.US"
            case .vix: ".VIX.US"
            // Longbridge returns 301600 for these index symbols; Composite's
            // generic per-symbol fallback can serve them from another provider.
            case .russell1000, .russell2000: nil
            case .hangSeng: "HSI.HK"
            case .hangSengTech: "HSTECH.HK"
            case .shanghaiComposite: "000001.SH"
            case .shenzhenComponent: "399001.SZ"
            case .chiNext: "399006.SZ"
            }
        }
        switch symbol.market {
        case .us:
            let code = symbol.code.uppercased()
            // Unknown Yahoo-style index codes stay with Yahoo instead of
            // poisoning an official SDK batch request.
            if code.hasPrefix("^") { return nil }
            if code.hasSuffix(".US") { return code }
            if code.hasPrefix(".") { return "\(code).US" }
            return "\(code).US"
        case .hk: return "\(symbol.code).HK"
        case .sh: return "\(symbol.code).SH"
        case .sz: return "\(symbol.code).SZ"
        case .crypto: return nil
        }
    }

    private static func usableAuth(_ auth: LongbridgeAuth?) -> LongbridgeAuth? {
        switch auth {
        case .apiKey(let credentials) where credentials.isComplete:
            auth
        case .oauth:
            auth
        default:
            nil
        }
    }
}
#endif
