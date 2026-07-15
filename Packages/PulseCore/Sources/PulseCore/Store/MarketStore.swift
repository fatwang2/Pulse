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
    /// Canonical current-session minute candles used by list rows and share cards.
    public private(set) var sparklines: [SymbolID: [Candle]] = [:]
    public private(set) var lastRefresh: Date?
    public private(set) var lastError: String?

    @ObservationIgnored private var candleCache: [CandleCacheKey: (candles: [Candle], fetchedAt: Date)] = [:]

    public init() {}

    public func quote(for symbol: SymbolID) -> Quote? { quotes[symbol] }

    public func apply(quotes newQuotes: [Quote]) {
        // Merge into a copy first, then assign once: a batch of quotes triggers only one view invalidation.
        // Writing entries one by one would re-render the list N times per tick (one of the culprits behind popover jank)
        var merged = quotes
        for quote in newQuotes where isFresher(quote, than: merged[quote.symbol]) {
            merged[quote.symbol] = quote
        }
        quotes = merged
        lastRefresh = .now
        lastError = nil
    }

    /// Merges push-delivered quotes (already coalesced upstream). Unlike a poll round it
    /// leaves `lastRefresh` and `lastError` alone — pushes are ticks, not health signals.
    public func applyStreamed(_ newQuotes: [Quote]) {
        var merged = quotes
        var changed = false
        for quote in newQuotes where isFresher(quote, than: merged[quote.symbol]) {
            merged[quote.symbol] = quote
            changed = true
        }
        if changed {
            quotes = merged
        }
    }

    /// Polls and pushes race: a poll served from a provider-side cache can arrive after a
    /// fresher push. Never let an older market timestamp overwrite a newer one.
    /// Timestamps are only comparable within one source, though — when the serving source
    /// changes (user toggled a provider, or routing failed over), the replacement carries
    /// the freshest data its source has, even if its market timestamp is older.
    private func isFresher(_ incoming: Quote, than existing: Quote?) -> Bool {
        guard let existing, incoming.sourceID == existing.sourceID else { return true }
        return incoming.timestamp >= existing.timestamp
    }

    public func apply(sparkline candles: [Candle], for symbol: SymbolID) {
        sparklines[symbol] = candles
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
