import Foundation
import Observation
import SwiftUI
import PulseCore
import PulseUI

/// iOS composition root: the same PulseCore engine the Mac app runs, minus the
/// Mac-only surfaces (menu bar, pinned window). Longbridge rides the statically
/// linked official SDK; free HTTP sources (Tencent/Yahoo/Binance) are always on.
@MainActor
@Observable
final class IOSAppState {
    let settings: IOSSettings
    let watchlist: WatchlistStore
    let market: MarketStore
    let engine: RefreshEngine
    @ObservationIgnored let provider: CompositeProvider
    @ObservationIgnored let binance: BinanceProvider
    @ObservationIgnored let longbridge: LongbridgeProvider
    @ObservationIgnored let longbridgeOAuth: LongbridgeOAuthAuthenticator

    enum LongbridgeAuthState {
        case none
        case apiKey
        case oauth
    }

    /// Which Longbridge auth mode is active; `.none` keeps the provider out of
    /// routing entirely.
    private(set) var longbridgeAuthState: LongbridgeAuthState
    var longbridgeConfigured: Bool { longbridgeAuthState != .none }
    private(set) var longbridgeConnectionStatus: LongbridgeConnectionStatus = .disconnected

    var palette: ChangePalette { ChangePalette(redUp: settings.redUp) }

    init() {
        let settings = IOSSettings()
        let watchlist = WatchlistStore()
        let market = MarketStore()
        let (auth, authState) = Self.loadLongbridgeAuth()
        let longbridge = LongbridgeProvider(auth: auth)
        let binance = BinanceProvider()
        var disabledIDs: Set<String> = []
        if authState == .none { disabledIDs.insert(LongbridgeProvider.providerID) }
        let provider = CompositeProvider(
            providers: [longbridge, binance, TencentProvider(), NaverProvider(), YahooProvider(), SinaProvider(), ShanghaiGoldExchangeProvider(), EastmoneyProvider()],
            disabledIDs: disabledIDs
        )
        self.settings = settings
        self.watchlist = watchlist
        self.market = market
        self.provider = provider
        self.binance = binance
        self.longbridge = longbridge
        self.longbridgeAuthState = authState
        // A distinct client name keeps this app tellable-apart from the Mac
        // entries in Longbridge's authorization-management list.
        self.longbridgeOAuth = LongbridgeOAuthAuthenticator(
            redirectScheme: Bundle.main.bundleIdentifier ?? "app.pulse.ios",
            clientName: Bundle.main.bundleIdentifier == "app.pulse.ios.dev"
                ? "Pulse iOS Dev"
                : "Pulse iOS"
        )
        self.engine = RefreshEngine(provider: provider, store: market, watchlist: watchlist)
        engine.start()
        Task { try? await binance.refreshSymbolCatalogIfNeeded() }
        Task { [weak self, longbridge] in
            let updates = await longbridge.connectionStatusUpdates()
            for await status in updates {
                guard let self else { return }
                self.longbridgeConnectionStatus = status
            }
        }
    }

    // MARK: - Longbridge auth

    /// OAuth tokens win over pasted API-key credentials when both exist.
    private static func loadLongbridgeAuth() -> (LongbridgeAuth?, LongbridgeAuthState) {
        if let tokens = LongbridgeCredentialStore.loadOAuthTokens() {
            return (.oauth(Self.makeOAuthSession(tokens)), .oauth)
        }
        if let credentials = LongbridgeCredentialStore.load(), credentials.isComplete {
            return (.apiKey(credentials), .apiKey)
        }
        return (nil, .none)
    }

    /// Refresh tokens rotate on every refresh; the session persists each rotation
    /// to the Keychain immediately so the chain survives relaunches.
    private static func makeOAuthSession(_ tokens: LongbridgeOAuthTokens) -> LongbridgeOAuthSession {
        LongbridgeOAuthSession(tokens: tokens) { rotated in
            try? LongbridgeCredentialStore.saveOAuthTokens(rotated)
        }
    }

    /// Runs the browser OAuth flow end to end: authorize → validate against the
    /// live gateway → persist. A failed attempt rolls back to whatever auth was
    /// active before. `openURL` receives the authorize page (the view drives it
    /// through ASWebAuthenticationSession).
    func connectLongbridgeOAuth(openURL: @Sendable @escaping (URL) -> Void) async throws {
        let tokens = try await longbridgeOAuth.authorize(openURL: openURL)
        try await activate(auth: .oauth(Self.makeOAuthSession(tokens)))
        try LongbridgeCredentialStore.saveOAuthTokens(tokens)
        LongbridgeCredentialStore.clear() // OAuth replaces any pasted API-key credentials
        longbridgeAuthState = .oauth
        applyProviderAvailability()
    }

    /// Forwards `bundleid://oauth/callback?...` URLs to the pending flow.
    func handleOAuthCallback(_ url: URL) {
        Task { _ = await longbridgeOAuth.handleCallback(url) }
    }

    private func activate(auth: LongbridgeAuth) async throws {
        await longbridge.updateAuth(auth)
        do {
            try await longbridge.validateConnection()
        } catch {
            await longbridge.updateAuth(Self.loadLongbridgeAuth().0)
            throw error
        }
    }

    func clearLongbridgeCredentials() {
        LongbridgeCredentialStore.clear()
        LongbridgeCredentialStore.clearOAuthTokens()
        longbridgeAuthState = .none
        Task {
            await longbridge.updateAuth(nil)
        }
        applyProviderAvailability()
    }

    /// Retries only the market-data transport; credentials stay intact.
    func retryLongbridgeConnection() {
        guard longbridgeConfigured else { return }
        Task {
            await longbridge.resetConnection()
            await provider.resetHealth(LongbridgeProvider.providerID)
            engine.poke()
            if watchlistOnScreen { restartWatchlistStream() }
        }
    }

    private func applyProviderAvailability() {
        var ids: Set<String> = []
        if !longbridgeConfigured { ids.insert(LongbridgeProvider.providerID) }
        Task {
            await provider.setDisabled(ids)
            engine.poke()
            if watchlistOnScreen { restartWatchlistStream() }
        }
    }

    // MARK: - Lifecycle

    /// Background apps must not keep polling: iOS suspends the process anyway,
    /// and a half-suspended loop would wake up mid-request. Stop cleanly and
    /// resume with an immediate full round on return.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if !engine.isRunning { engine.start() }
            engine.poke()
            if watchlistOnScreen { restartWatchlistStream() }
        case .background:
            engine.stop()
            stopWatchlistStream()
        default:
            break
        }
    }

    // MARK: - Live watchlist stream

    @ObservationIgnored private var watchlistStreamTask: Task<Void, Never>?
    @ObservationIgnored private var watchlistStreamSessionID: UUID?
    @ObservationIgnored private var watchlistOnScreen = false
    @ObservationIgnored private var pendingPushes: [SymbolID: Quote] = [:]
    @ObservationIgnored private var pushFlushTask: Task<Void, Never>?

    /// True while a configured live source is connected or delivering.
    private(set) var liveStreaming = false

    func setWatchlistVisible(_ visible: Bool) {
        guard watchlistOnScreen != visible else { return }
        watchlistOnScreen = visible
        if visible {
            restartWatchlistStream()
        } else {
            stopWatchlistStream()
        }
    }

    /// Re-subscribes after watchlist edits while the list is on screen.
    func watchlistSymbolsChanged() {
        engine.poke()
        guard watchlistOnScreen else { return }
        restartWatchlistStream()
    }

    private func stopWatchlistStream() {
        watchlistStreamTask?.cancel()
        watchlistStreamTask = nil
        watchlistStreamSessionID = nil
    }

    private func restartWatchlistStream() {
        stopWatchlistStream()
        let symbols = watchlist.symbols
        guard hasEnabledStreamingProvider(for: symbols),
              let stream = provider.quoteStream(for: symbols) else {
            liveStreaming = false
            return
        }
        liveStreaming = true
        let sessionID = UUID()
        watchlistStreamSessionID = sessionID
        watchlistStreamTask = Task { [weak self] in
            do {
                for try await quote in stream {
                    guard self?.watchlistStreamSessionID == sessionID else { return }
                    self?.liveStreaming = true
                    self?.ingestStreamedQuote(quote)
                }
            } catch {
                // Stream dropped (socket reconnect etc.); polling still covers the list.
            }
            guard let self, self.watchlistStreamSessionID == sessionID else { return }
            self.watchlistStreamTask = nil
            self.watchlistStreamSessionID = nil
            if !Task.isCancelled {
                self.liveStreaming = false
            }
        }
    }

    private func hasEnabledStreamingProvider(for symbols: [SymbolID]) -> Bool {
        provider.registeredDescriptors.contains { descriptor in
            descriptor.capabilities.contains(.streaming)
                && (descriptor.id != LongbridgeProvider.providerID || longbridgeConfigured)
                && symbols.contains { descriptor.supports(.streaming, in: $0.market) }
        }
    }

    /// Pushes arrive per tick and per symbol; a short buffer keeps a busy market
    /// from re-rendering the list dozens of times per second.
    func ingestStreamedQuote(_ quote: Quote) {
        pendingPushes[quote.symbol] = quote
        guard pushFlushTask == nil else { return }
        pushFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            self.pushFlushTask = nil
            self.flushPendingPushes()
        }
    }

    private func flushPendingPushes() {
        guard !pendingPushes.isEmpty else { return }
        let batch = Array(pendingPushes.values)
        pendingPushes = [:]
        applyQuoteNameUpgrades(batch)
        market.applyStreamed(batch)
    }

    private func applyQuoteNameUpgrades(_ quotes: [Quote]) {
        for quote in quotes {
            guard let name = quote.name,
                  let providerID = quote.sourceID,
                  let source = provider.displayNameSource(
                    for: providerID,
                    market: quote.symbol.market
                  ) else {
                continue
            }
            watchlist.upgradeDisplayName(for: quote.symbol, to: name, source: source)
        }
    }

    // MARK: - Presentation helpers (mirrors the Mac AppState)

    /// One presentation name per instrument, independent of whichever provider
    /// currently supplies its price.
    func displayName(for symbol: SymbolID) -> String {
        if let item = watchlist.item(for: symbol) {
            return item.resolvedDisplayName
        }
        if let index = symbol.indexID {
            return index.displayName
        }
        if let metal = symbol.metalID {
            return metal.displayName
        }
        return market.quote(for: symbol)?.name ?? symbol.displayCode
    }

    /// Calculated benchmarks, not traded securities: catalog indices carry an
    /// `indexID`; search-classified ones rely on the stored instrument type.
    func isIndex(_ symbol: SymbolID) -> Bool {
        symbol.indexID != nil || watchlist.item(for: symbol)?.resolvedInstrumentType == .index
    }

    /// The US pre/post setting only applies to instruments that trade those
    /// sessions; indices compute during regular hours only.
    func showsExtendedHours(for symbol: SymbolID) -> Bool {
        settings.showsUSExtendedHours && symbol.market == .us && !isIndex(symbol)
    }

    /// Minimum quote delay (in seconds) for a market: fallback only when the
    /// active quote source is unknown.
    func quoteDelay(for market: Market) -> TimeInterval {
        let delays = provider.registeredDescriptors
            .filter { $0.supports(.quotes, in: market) }
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
        } else if let sourceID = quote.sourceID,
                  let descriptor = provider.registeredDescriptors.first(where: { $0.id == sourceID }),
                  let seconds = descriptor.pollingCadenceSeconds(
                      interval: engine.pollInterval(for: sourceID)
                  ) {
            // A polled source is current but steps; "realtime" alone would
            // promise a ticking price it cannot deliver.
            parts.append(PulseLocalization.localizedString("quote.cadence.seconds", seconds))
        }
        return parts.joined(separator: " · ")
    }

    func quoteMarketTimeText(for quote: Quote) -> String {
        let market = quote.symbol.market
        return "\(formatMarketTime(quote.timestamp, market: market)) \(market.timeZoneDisplayName)"
    }

    private func formatMarketTime(_ date: Date, market: Market) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = market.timeZone
        return formatter.string(from: date)
    }

    // MARK: - Search

    /// Errors are surfaced by the UI (to distinguish "no results" from "provider error").
    func search(_ query: String) async throws -> [SymbolInfo] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var results = try await provider.search(query)
        guard !results.isEmpty,
              let preferredNames = try? await provider.preferredSecurityNames(
                for: results.map(\.symbol)
              ) else {
            return results
        }
        let namesBySymbol = Dictionary(
            uniqueKeysWithValues: preferredNames.map { ($0.symbol, $0) }
        )
        for index in results.indices {
            guard let preferred = namesBySymbol[results[index].symbol] else { continue }
            let currentPriority = results[index].displayNameSource?.priority ?? Int.max
            if preferred.source.priority <= currentPriority {
                results[index].name = preferred.name
                results[index].displayNameSource = preferred.source
            }
        }
        return results
    }
}
