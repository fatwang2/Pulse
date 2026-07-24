import Foundation

public enum Capability: String, Codable, Sendable, Hashable {
    case search
    /// Static reference data for known symbols, including canonical localized names.
    case referenceData
    case quotes
    case candles
    case streaming
}

/// A credential field the user must supply for a data source (e.g. a Longbridge App Key)
public struct CredentialField: Codable, Sendable, Hashable {
    public var key: String
    public var label: String
    public var secure: Bool

    public init(key: String, label: String, secure: Bool = true) {
        self.key = key
        self.label = label
        self.secure = secure
    }
}

/// Rate-limit policy self-declared by a data source; RefreshEngine throttles accordingly
public struct RateLimitPolicy: Codable, Sendable, Hashable {
    /// Suggested minimum interval between requests (seconds)
    public var minInterval: TimeInterval
    /// Maximum number of symbols per batch request (nil = batching not supported)
    public var batchSize: Int?

    public init(minInterval: TimeInterval, batchSize: Int? = nil) {
        self.minInterval = minInterval
        self.batchSize = batchSize
    }
}

/// Provider self-description: the single source of truth for routing, capability negotiation, and the settings page.
/// It is also the deserialization target for future plugins' (Manifest / JS) manifest.json.
public struct ProviderDescriptor: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var markets: Set<Market>
    public var capabilities: Set<Capability>
    /// Optional candle-specific coverage. Nil means every declared market / period.
    public var candleMarkets: Set<Market>?
    public var candlePeriods: Set<CandlePeriod>?
    /// Data delay per market (seconds), 0 = real time
    public var delay: [Market: TimeInterval]
    public var rateLimit: RateLimitPolicy?
    public var credentials: [CredentialField]
    /// Default quote-poll cadence for this source (seconds). The user can override it per
    /// provider; sources with push streaming only need polling as reconciliation.
    public var suggestedPollInterval: TimeInterval?
    /// Markets this source keeps quoting during the overnight session (currently a US
    /// concept). Other sources are simply not polled overnight.
    public var overnightMarkets: Set<Market>

    public init(id: String, name: String, markets: Set<Market>, capabilities: Set<Capability>,
                candleMarkets: Set<Market>? = nil, candlePeriods: Set<CandlePeriod>? = nil,
                delay: [Market: TimeInterval] = [:], rateLimit: RateLimitPolicy? = nil,
                credentials: [CredentialField] = [], suggestedPollInterval: TimeInterval? = nil,
                overnightMarkets: Set<Market> = []) {
        self.id = id
        self.name = name
        self.markets = markets
        self.capabilities = capabilities
        self.candleMarkets = candleMarkets
        self.candlePeriods = candlePeriods
        self.delay = delay
        self.rateLimit = rateLimit
        self.credentials = credentials
        self.suggestedPollInterval = suggestedPollInterval
        self.overnightMarkets = overnightMarkets
    }

    /// How fresh this source's data is across its markets, for display.
    public enum DelayClass {
        /// Every covered market is zero-delay
        case realtime
        /// Some markets are zero-delay, others delayed
        case partiallyRealtime
        /// No market is zero-delay
        case delayed
    }

    public var delayClass: DelayClass {
        let delays = markets.map { delay[$0] ?? 0 }
        if delays.allSatisfy({ $0 == 0 }) { return .realtime }
        if delays.contains(0) { return .partiallyRealtime }
        return .delayed
    }

    public func supports(_ capability: Capability, in market: Market) -> Bool {
        guard capabilities.contains(capability), markets.contains(market) else { return false }
        if capability == .candles, let candleMarkets {
            return candleMarkets.contains(market)
        }
        return true
    }

    public func supports(candles period: CandlePeriod, in market: Market) -> Bool {
        supports(.candles, in: market) && (candlePeriods?.contains(period) ?? true)
    }
}
