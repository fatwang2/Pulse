import Foundation
import Observation

/// Refresh scheduling: a trading-session-aware polling loop.
/// Providers handle HOW to fetch data; this handles WHEN. Each data source polls at its own
/// cadence (user override → descriptor suggestion → 15s default): the scheduler ticks on a
/// short base interval, groups the watchlist by preferred provider, and polls exactly the
/// groups whose cadence has elapsed. Sparklines refresh on their own low-frequency track.
@MainActor
@Observable
public final class RefreshEngine {
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
    @ObservationIgnored private var lastPollAt: [String: Date] = [:]
    @ObservationIgnored private var pollOverrides: [String: TimeInterval]
    @ObservationIgnored private lazy var suggestedIntervals: [String: TimeInterval] = {
        Dictionary(uniqueKeysWithValues: provider.registeredDescriptors.compactMap { descriptor in
            descriptor.suggestedPollInterval.map { (descriptor.id, $0) }
        })
    }()

    private static let fallbackPollInterval: TimeInterval = 15
    /// Scheduler resolution while any covered market trades; also the fastest selectable cadence
    private static let baseTick: TimeInterval = 5

    public init(provider: CompositeProvider, store: MarketStore, watchlist: WatchlistStore,
                pollOverrides: [String: TimeInterval] = [:]) {
        self.provider = provider
        self.store = store
        self.watchlist = watchlist
        self.pollOverrides = pollOverrides
    }

    /// Effective quote cadence for one source: user override → descriptor suggestion → default.
    public func pollInterval(for providerID: String) -> TimeInterval {
        pollOverrides[providerID] ?? suggestedIntervals[providerID] ?? Self.fallbackPollInterval
    }

    public func setPollOverride(_ interval: TimeInterval?, for providerID: String) {
        pollOverrides[providerID] = interval
        lastPollAt[providerID] = nil // apply the new cadence right away
        poke()
    }

    public func start() {
        guard loopTask == nil else { return }
        isRunning = true
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let markets = Set(self.watchlist.symbols.map(\.market))
                // Wake at scheduler resolution while trading; slow down off-hours (the
                // per-symbol worth-refreshing filter keeps off-hour ticks request-free).
                let interval = TradingCalendar.anyActive(markets) ? Self.baseTick : 60
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
        lastPollAt = [:] // a poke means "refresh everything now", regardless of cadence
        start()
    }

    private func tick() async {
        let symbols = watchlist.symbols
        guard !symbols.isEmpty else { return }

        let routing = await provider.quoteRouting(for: symbols)
        let overnightByProvider = Dictionary(uniqueKeysWithValues: provider.registeredDescriptors.map {
            ($0.id, $0.overnightMarkets)
        })
        for (providerID, group) in routing {
            let last = lastPollAt[providerID] ?? .distantPast
            guard Date.now.timeIntervalSince(last) >= pollInterval(for: providerID) else { continue }

            let quoteSymbols = symbolsWorthRefreshing(group, overnightMarkets: overnightByProvider[providerID] ?? [])
            guard !quoteSymbols.isEmpty else { continue }
            lastPollAt[providerID] = .now
            do {
                let quotes = try await provider.quotes(for: quoteSymbols)
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
        }

        await refreshSparklinesIfDue(symbols: symbols)
    }

    private func symbolsWorthRefreshing(_ symbols: [SymbolID], overnightMarkets: Set<Market>) -> [SymbolID] {
        let now = Date.now
        return symbols.filter { symbol in
            if store.quote(for: symbol) == nil { return true }
            if TradingCalendar.isActive(symbol.market, at: now) { return true }
            // Overnight polls only against sources that actually quote the session
            if overnightMarkets.contains(symbol.market),
               TradingCalendar.state(of: symbol.market, at: now) == .overnight { return true }
            return TradingCalendar.isActive(symbol.market, at: now.addingTimeInterval(-35 * 60))
        }
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
