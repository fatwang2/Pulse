import Foundation

public enum Capability: String, Codable, Sendable, Hashable {
    case search
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

    public init(id: String, name: String, markets: Set<Market>, capabilities: Set<Capability>,
                candleMarkets: Set<Market>? = nil, candlePeriods: Set<CandlePeriod>? = nil,
                delay: [Market: TimeInterval] = [:], rateLimit: RateLimitPolicy? = nil,
                credentials: [CredentialField] = []) {
        self.id = id
        self.name = name
        self.markets = markets
        self.capabilities = capabilities
        self.candleMarkets = candleMarkets
        self.candlePeriods = candlePeriods
        self.delay = delay
        self.rateLimit = rateLimit
        self.credentials = credentials
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
