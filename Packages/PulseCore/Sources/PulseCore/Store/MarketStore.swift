import Foundation
import Observation

public struct CandleCacheKey: Hashable, Sendable {
    public var symbol: SymbolID
    public var period: CandlePeriod

    public init(symbol: SymbolID, period: CandlePeriod) {
        self.symbol = symbol
        self.period = period
    }
}

/// In-memory quote store: the single data surface for the UI. All surfaces (menu bar / popover / future in-process widgets) read the same instance.
@MainActor
@Observable
public final class MarketStore {
    public private(set) var quotes: [SymbolID: Quote] = [:]
    /// Intraday close series used for the sparkline in list rows
    public private(set) var sparklines: [SymbolID: [Double]] = [:]
    public private(set) var lastRefresh: Date?
    public private(set) var lastError: String?

    @ObservationIgnored private var candleCache: [CandleCacheKey: (candles: [Candle], fetchedAt: Date)] = [:]

    public init() {}

    public func quote(for symbol: SymbolID) -> Quote? { quotes[symbol] }

    public func apply(quotes newQuotes: [Quote]) {
        // Merge into a copy first, then assign once: a batch of quotes triggers only one view invalidation.
        // Writing entries one by one would re-render the list N times per tick (one of the culprits behind popover jank)
        var merged = quotes
        for quote in newQuotes {
            merged[quote.symbol] = quote
        }
        quotes = merged
        lastRefresh = .now
        lastError = nil
    }

    public func apply(sparkline values: [Double], for symbol: SymbolID) {
        sparklines[symbol] = values
    }

    public func reportError(_ message: String) {
        lastError = message
    }

    // MARK: - Candle cache

    public func cachedCandles(for key: CandleCacheKey, maxAge: TimeInterval) -> [Candle]? {
        guard let entry = candleCache[key], Date.now.timeIntervalSince(entry.fetchedAt) < maxAge else {
            return nil
        }
        return entry.candles
    }

    public func cache(candles: [Candle], for key: CandleCacheKey) {
        candleCache[key] = (candles, .now)
    }
}
