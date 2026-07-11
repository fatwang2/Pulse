import Foundation

public enum MarketState: String, Codable, Sendable {
    case preMarket, regular, postMarket, closed
}

/// A single quote snapshot. change/changePercent are derived from price and previousClose to avoid inconsistent definitions across data sources.
public struct Quote: Codable, Sendable, Hashable {
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

    public init(symbol: SymbolID, name: String? = nil, price: Double, previousClose: Double,
                open: Double? = nil, high: Double? = nil, low: Double? = nil,
                volume: Double? = nil, turnover: Double? = nil,
                currencyCode: String? = nil, sourceID: String? = nil, sourceName: String? = nil,
                sourceDelay: TimeInterval? = nil, timestamp: Date = .now, marketState: MarketState? = nil) {
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
    }

    public func sourced(by descriptor: ProviderDescriptor) -> Quote {
        var quote = self
        quote.sourceID = descriptor.id
        quote.sourceName = descriptor.name
        quote.sourceDelay = descriptor.delay[symbol.market]
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
