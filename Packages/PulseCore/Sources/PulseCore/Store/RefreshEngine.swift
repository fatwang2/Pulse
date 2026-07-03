import Foundation
import Observation

/// Refresh scheduling: a trading-session-aware polling loop.
/// Providers handle HOW to fetch data; this handles WHEN — throttling, slowing down when idle, and low-frequency sparkline refreshes alongside quotes.
@MainActor
@Observable
public final class RefreshEngine {
    /// Refresh interval while markets are open (seconds), user-configurable
    public var activeInterval: TimeInterval {
        didSet { poke() }
    }

    /// Polling interval when all markets are closed (waiting for the open / next day)
    public var idleInterval: TimeInterval = 300

    /// Refresh interval for sparklines (intraday close series)
    public var sparklineInterval: TimeInterval = 300

    public private(set) var isRunning = false

    @ObservationIgnored private let provider: CompositeProvider
    @ObservationIgnored private let store: MarketStore
    @ObservationIgnored private let watchlist: WatchlistStore
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var lastSparklineAt: [SymbolID: Date] = [:]

    public init(provider: CompositeProvider, store: MarketStore, watchlist: WatchlistStore,
                activeInterval: TimeInterval = 15) {
        self.provider = provider
        self.store = store
        self.watchlist = watchlist
        self.activeInterval = activeInterval
    }

    public func start() {
        guard loopTask == nil else { return }
        isRunning = true
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = self.currentInterval()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
    }

    /// Triggers a refresh round immediately (called after adding a watchlist item or changing settings)
    public func poke() {
        guard loopTask != nil else { return }
        loopTask?.cancel()
        loopTask = nil
        start()
    }

    private func currentInterval() -> TimeInterval {
        let markets = Set(watchlist.symbols.map(\.market))
        if TradingCalendar.anyActive(markets) { return activeInterval }
        // Post-close settlement window: free sources are delayed ~15 minutes intraday, so quotes take a while after the close to converge on the official closing price.
        // Keep a medium refresh rate for 35 minutes after the close so closing prices align quickly, instead of dropping straight to the 5-minute idle poll.
        let wasActiveRecently = TradingCalendar.anyActive(markets, at: .now.addingTimeInterval(-35 * 60))
        return wasActiveRecently ? 60 : idleInterval
    }

    private func tick() async {
        let symbols = watchlist.symbols
        guard !symbols.isEmpty else { return }

        do {
            let quotes = try await provider.quotes(for: symbols)
            store.apply(quotes: quotes)
            // Write the latest name from quotes back to the watchlist (the search-result name captured at add time can be rough)
            for quote in quotes {
                if let name = quote.name {
                    watchlist.updateDisplayName(quote.symbol, name: name)
                }
            }
        } catch {
            store.reportError(String(describing: error))
        }

        await refreshSparklinesIfDue(symbols: symbols)
    }

    private func refreshSparklinesIfDue(symbols: [SymbolID]) async {
        var fetched = 0
        for symbol in symbols {
            let last = lastSparklineAt[symbol] ?? .distantPast
            // A closed market's sparkline doesn't change; skip fetching if we already have data
            let active = TradingCalendar.isActive(symbol.market)
            let hasData = !(store.sparklines[symbol]?.isEmpty ?? true)
            guard Date.now.timeIntervalSince(last) >= sparklineInterval, active || !hasData else { continue }

            // Record the time regardless of success: symbols a source lacks (e.g. A-share indices missing from Yahoo) shouldn't be retried over and over
            lastSparklineAt[symbol] = .now
            if let candles = try? await provider.candles(for: symbol, period: .minute5, count: 60) {
                store.apply(sparkline: candles.map(\.close), for: symbol)
            }
            // Fetch one at a time with a gap in between to avoid a request burst against a single source (which would trigger rate limiting)
            fetched += 1
            if fetched >= 6 { break }
            try? await Task.sleep(for: .milliseconds(350))
        }
    }

    // MARK: - On-demand detail chart loading (called when the popover opens a detail view)

    public func loadCandles(for symbol: SymbolID, period: CandlePeriod, count: Int = 120) async -> [Candle] {
        let key = CandleCacheKey(symbol: symbol, period: period)
        let maxAge: TimeInterval = period.isIntraday ? 60 : 600
        if let cached = store.cachedCandles(for: key, maxAge: maxAge) {
            return cached
        }
        do {
            let candles = try await provider.candles(for: symbol, period: period, count: count)
            store.cache(candles: candles, for: key)
            return candles
        } catch {
            store.reportError(String(describing: error))
            return store.cachedCandles(for: key, maxAge: .infinity) ?? []
        }
    }
}
