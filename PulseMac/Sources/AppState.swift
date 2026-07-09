import Foundation
import Observation
import PulseCore
import PulseUI

@MainActor
@Observable
final class AppState {
    let settings: AppSettings
    let watchlist: WatchlistStore
    let market: MarketStore
    let engine: RefreshEngine
    @ObservationIgnored let provider: CompositeProvider

    private(set) var rotationIndex = 0
    @ObservationIgnored private var rotationTask: Task<Void, Never>?

    var palette: ChangePalette { ChangePalette(redUp: settings.redUp) }

    init() {
        let settings = AppSettings()
        let watchlist = WatchlistStore()
        let market = MarketStore()
        let provider = CompositeProvider(providers: [TencentProvider(), YahooProvider()],
                                         disabledIDs: settings.disabledProviderIDs)
        self.settings = settings
        self.watchlist = watchlist
        self.market = market
        self.provider = provider
        self.engine = RefreshEngine(provider: provider, store: market, watchlist: watchlist,
                                    activeInterval: settings.refreshInterval)
        engine.start()
        startRotation()
    }

    // MARK: - Provider toggles

    var providerDescriptors: [ProviderDescriptor] { provider.registeredDescriptors }

    func isProviderEnabled(_ id: String) -> Bool {
        !settings.disabledProviderIDs.contains(id)
    }

    func setProvider(_ id: String, enabled: Bool) {
        if enabled {
            settings.disabledProviderIDs.remove(id)
        } else {
            settings.disabledProviderIDs.insert(id)
        }
        let ids = settings.disabledProviderIDs
        Task {
            await provider.setDisabled(ids)
            engine.poke()
        }
    }

    // MARK: - Menu bar text

    var menuBarItem: WatchItem? {
        let items = watchlist.items
        guard !items.isEmpty else { return nil }
        switch settings.menuBarMode {
        case .compact:
            return nil
        case .single:
            if let primary = settings.primarySymbol,
               let item = items.first(where: { $0.symbol == primary }) {
                return item
            }
            return items.first
        case .rotate:
            return items[rotationIndex % items.count]
        }
    }

    var menuBarText: String {
        guard let item = menuBarItem else { return "Pulse" }
        guard let quote = market.quote(for: item.symbol) else {
            return shortName(for: item)
        }
        let arrow = PriceFormatter.arrow(quote.change)
        let percent = abs(quote.changePercent).formatted(.number.precision(.fractionLength(2)))
        return "\(shortName(for: item)) \(PriceFormatter.price(quote.price)) \(arrow)\(percent)%"
    }

    private func shortName(for item: WatchItem) -> String {
        // US stocks use the ticker (AAPL is shorter than "Apple Inc."); Chinese names are truncated to the first 5 characters
        if item.symbol.market == .us { return item.symbol.code }
        return String(item.displayName.prefix(5))
    }

    // MARK: - Rotation

    private func startRotation() {
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.settings.rotateInterval ?? 6
                try? await Task.sleep(for: .seconds(interval))
                guard let self, self.settings.menuBarMode == .rotate else { continue }
                let count = self.watchlist.items.count
                guard count > 0 else { continue }
                self.rotationIndex = (self.rotationIndex + 1) % count
            }
        }
    }

    // MARK: - Settings wiring

    func applyRefreshInterval(_ interval: TimeInterval) {
        settings.refreshInterval = interval
        engine.activeInterval = interval
    }

    /// Minimum quote delay (in seconds) for a market: fallback only when the active quote source is unknown.
    func quoteDelay(for market: Market) -> TimeInterval {
        let delays = provider.registeredDescriptors
            .filter { !settings.disabledProviderIDs.contains($0.id) && $0.supports(.quotes, in: market) }
            .compactMap { $0.delay[market] }
        return delays.min() ?? 0
    }

    func quoteDelay(for quote: Quote) -> TimeInterval {
        quote.sourceDelay ?? quoteDelay(for: quote.symbol.market)
    }

    func quoteTimingText(for quote: Quote) -> String {
        var parts = [PulseLocalization.localizedString(
            "quote.timing.market",
            quoteMarketTimeText(for: quote)
        )]
        if let sourceName = quote.sourceName {
            parts.append(sourceName)
        }
        let delay = quoteDelay(for: quote)
        if delay > 0 {
            parts.append(PulseLocalization.localizedString("quote.delay.minutes", Int(delay / 60)))
        }
        return parts.joined(separator: " · ")
    }

    func quoteMarketTimeText(for quote: Quote) -> String {
        let market = quote.symbol.market
        return "\(formatMarketTime(quote.timestamp, market: market)) \(market.timeZoneDisplayName)"
    }

    func quoteDelayText(for quote: Quote) -> String? {
        let delay = quoteDelay(for: quote)
        guard delay > 0 else { return nil }
        return PulseLocalization.localizedString("quote.delay.minutes", Int(delay / 60))
    }

    func refreshTimingText() -> String? {
        guard let refreshed = market.lastRefresh else { return nil }
        return PulseLocalization.localizedString(
            "refresh.updatedAt",
            refreshed.formatted(date: .omitted, time: .standard)
        )
    }

    private func formatMarketTime(_ date: Date, market: Market) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = market.timeZone
        return formatter.string(from: date)
    }

    // MARK: - Search

    /// Errors are surfaced by the UI (to distinguish "no results" from "provider error")
    func search(_ query: String) async throws -> [SymbolInfo] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return try await provider.search(query)
    }
}
