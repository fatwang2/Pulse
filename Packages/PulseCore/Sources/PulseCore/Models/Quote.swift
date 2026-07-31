import Foundation

public enum MarketState: String, Codable, Sendable {
    case preMarket, regular, postMarket, closed
    /// US overnight session (Sun–Thu 20:00 → 04:00 ET); only some sources quote it
    case overnight
}

/// A single quote snapshot. change/changePercent are derived from price and previousClose to avoid inconsistent definitions across data sources.
public struct Quote: Codable, Sendable, Hashable {
    /// The most recent completed regular session, attached to extended-session
    /// quotes (pre/post/overnight) so surfaces can show that day's result
    /// alongside the live extended price. `previousClose` is the close that
    /// session traded against; nil when the source cannot supply it (the
    /// session's own change is then unknown).
    public struct RegularSessionClose: Codable, Sendable, Hashable {
        public var price: Double
        public var previousClose: Double?

        public init(price: Double, previousClose: Double? = nil) {
            self.price = price
            self.previousClose = previousClose
        }

        public var change: Double? {
            previousClose.map { price - $0 }
        }

        public var changePercent: Double? {
            guard let previousClose, previousClose != 0 else { return nil }
            return (price - previousClose) / previousClose * 100
        }
    }

    public var symbol: SymbolID
    public var name: String?
    public var price: Double
    public var previousClose: Double
    public var open: Double?
    public var high: Double?
    public var low: Double?
    /// Trading volume (in shares)
    public var volume: Double?
    /// Turnover (in the market's local currency)
    public var turnover: Double?
    public var currencyCode: String?
    public var sourceID: String?
    public var sourceName: String?
    public var sourceDelay: TimeInterval?
    public var timestamp: Date
    public var marketState: MarketState?
    /// Present only when `marketState` is an extended session (pre/post/overnight).
    public var regularSession: RegularSessionClose?

    public init(symbol: SymbolID, name: String? = nil, price: Double, previousClose: Double,
                open: Double? = nil, high: Double? = nil, low: Double? = nil,
                volume: Double? = nil, turnover: Double? = nil,
                currencyCode: String? = nil, sourceID: String? = nil, sourceName: String? = nil,
                sourceDelay: TimeInterval? = nil, timestamp: Date = .now, marketState: MarketState? = nil,
                regularSession: RegularSessionClose? = nil) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.previousClose = previousClose
        self.open = open
        self.high = high
        self.low = low
        self.volume = volume
        self.turnover = turnover
        self.currencyCode = currencyCode
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.sourceDelay = sourceDelay
        self.timestamp = timestamp
        self.marketState = marketState
        self.regularSession = regularSession
    }

    public func sourced(by descriptor: ProviderDescriptor) -> Quote {
        var quote = self
        quote.sourceID = descriptor.id
        quote.sourceName = descriptor.name
        // A provider may negotiate a session-specific quote package (Longbridge)
        // or detect delay from the returned market timestamp. Preserve that runtime
        // provenance; the static descriptor is only the fallback.
        quote.sourceDelay = quote.sourceDelay ?? descriptor.delay[symbol.market]
        return quote
    }

    public var change: Double { price - previousClose }

    public var changePercent: Double {
        guard previousClose != 0 else { return 0 }
        return change / previousClose * 100
    }

    /// Today's high-low range as a percentage of the previous close.
    /// This is provider-independent because both quote sources expose high, low, and previous close.
    public var amplitudePercent: Double? {
        guard let high, let low, previousClose > 0, high >= low else { return nil }
        return (high - low) / previousClose * 100
    }
}
