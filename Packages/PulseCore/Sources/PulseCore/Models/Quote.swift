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
    public var timestamp: Date
    public var marketState: MarketState?

    public init(symbol: SymbolID, name: String? = nil, price: Double, previousClose: Double,
                open: Double? = nil, high: Double? = nil, low: Double? = nil,
                volume: Double? = nil, turnover: Double? = nil,
                currencyCode: String? = nil, timestamp: Date = .now, marketState: MarketState? = nil) {
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
        self.timestamp = timestamp
        self.marketState = marketState
    }

    public var change: Double { price - previousClose }

    public var changePercent: Double {
        guard previousClose != 0 else { return 0 }
        return change / previousClose * 100
    }
}
