import AppKit
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
    @ObservationIgnored let binance: BinanceProvider
    @ObservationIgnored let longbridge: LongbridgeProvider
    @ObservationIgnored let longbridgeOAuth: LongbridgeOAuthAuthenticator

    enum LongbridgeAuthState {
        case none
        case apiKey
        case oauth
    }

    /// Which Longbridge auth mode is active; `.none` keeps the provider out of routing
    /// regardless of the user's enable toggle.
    private(set) var longbridgeAuthState: LongbridgeAuthState
    var longbridgeConfigured: Bool { longbridgeAuthState != .none }

    private(set) var rotationIndex = 0
    @ObservationIgnored private var rotationTask: Task<Void, Never>?

    var palette: ChangePalette { ChangePalette(redUp: settings.redUp) }

    init() {
        let settings = AppSettings()
        let watchlist = WatchlistStore()
        let market = MarketStore()
        // Image-rendering self-tests do not need live credentials. Skipping Keychain access
        // also keeps the headless test from waiting on an authorization prompt.
        let authContext: (LongbridgeAuth?, LongbridgeAuthState) = CommandLine.arguments.contains("--share-selftest")
            ? (nil, .none)
            : Self.loadLongbridgeAuth()
        let (auth, authState) = authContext
        let longbridge = LongbridgeProvider(auth: auth)
        let binance = BinanceProvider()
        var disabledIDs = settings.disabledProviderIDs
        if authState == .none { disabledIDs.insert(LongbridgeProvider.providerID) }
        let provider = CompositeProvider(providers: [longbridge, binance, TencentProvider(), YahooProvider()],
                                         disabledIDs: disabledIDs)
        self.settings = settings
        self.watchlist = watchlist
        self.market = market
        self.provider = provider
        self.binance = binance
        self.longbridge = longbridge
        self.longbridgeAuthState = authState
        self.longbridgeOAuth = LongbridgeOAuthAuthenticator(
            redirectScheme: Bundle.main.bundleIdentifier ?? "app.pulse.mac",
            clientName: "Pulse"
        )
        self.engine = RefreshEngine(provider: provider, store: market, watchlist: watchlist,
                                    pollOverrides: settings.providerPollIntervals)
        self.liveStreaming = false
        engine.start()
        startRotation()
        observeMenuTracking()
        if !disabledIDs.contains(BinanceProvider.providerID),
           !CommandLine.arguments.contains("--share-selftest") {
            Task { try? await binance.refreshSymbolCatalogIfNeeded() }
        }
    }

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

    /// Refresh tokens rotate on every refresh; the session persists each rotation to the
    /// Keychain immediately so the chain survives relaunches.
    private static func makeOAuthSession(_ tokens: LongbridgeOAuthTokens) -> LongbridgeOAuthSession {
        LongbridgeOAuthSession(tokens: tokens) { rotated in
            try? LongbridgeCredentialStore.saveOAuthTokens(rotated)
        }
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
        applyProviderAvailability()
        if enabled, id == BinanceProvider.providerID {
            Task { try? await binance.refreshSymbolCatalogIfNeeded() }
        }
    }

    /// User intent (enable toggles) combined with configuration state: an unconfigured
    /// Longbridge never participates in routing.
    private func effectiveDisabledIDs() -> Set<String> {
        var ids = settings.disabledProviderIDs
        if !longbridgeConfigured { ids.insert(LongbridgeProvider.providerID) }
        return ids
    }

    private func applyProviderAvailability() {
        let ids = effectiveDisabledIDs()
        Task {
            await provider.setDisabled(ids)
            engine.poke()
            // A push subscription checks availability only when it starts, so an
            // already-running stream would keep delivering from a source the user
            // just turned off — resubscribe against the new availability.
            if isPopoverVisible { restartWatchlistStream() }
        }
    }

    // MARK: - Longbridge auth

    /// Runs the browser OAuth flow end to end: authorize → validate against the live
    /// gateway → persist. A failed attempt rolls back to whatever auth was active before.
    func connectLongbridgeOAuth() async throws {
        let tokens = try await longbridgeOAuth.authorize { url in
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        try await activate(auth: .oauth(Self.makeOAuthSession(tokens)))
        try LongbridgeCredentialStore.saveOAuthTokens(tokens)
        LongbridgeCredentialStore.clear() // OAuth replaces any pasted API-key credentials
        longbridgeAuthState = .oauth
        // Connecting is the strongest possible "turn this on" signal — flip the
        // switch that was locked off while unconfigured.
        setProvider(LongbridgeProvider.providerID, enabled: true)
    }

    /// Forwards `bundleid://oauth/callback?...` URLs from the system to the pending flow.
    func handleOAuthCallback(_ url: URL) {
        Task { _ = await longbridgeOAuth.handleCallback(url) }
    }

    /// Validates against the live gateway before persisting; invalid credentials are rolled
    /// back so a previously working configuration is never destroyed by a failed edit.
    func saveLongbridgeCredentials(_ credentials: LongbridgeCredentials) async throws {
        try await activate(auth: .apiKey(credentials))
        try LongbridgeCredentialStore.save(credentials)
        LongbridgeCredentialStore.clearOAuthTokens() // manual credentials replace OAuth
        longbridgeAuthState = .apiKey
        setProvider(LongbridgeProvider.providerID, enabled: true)
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

    func pollInterval(for providerID: String) -> TimeInterval {
        engine.pollInterval(for: providerID)
    }

    func setPollInterval(_ interval: TimeInterval, for providerID: String) {
        settings.providerPollIntervals[providerID] = interval
        engine.setPollOverride(interval, for: providerID)
    }

    // MARK: - Live watchlist (push-first home page)

    @ObservationIgnored private var watchlistStreamTask: Task<Void, Never>?
    @ObservationIgnored private var watchlistStreamSessionID: UUID?
    @ObservationIgnored private var isPopoverVisible = false
    @ObservationIgnored private var pendingPushes: [SymbolID: Quote] = [:]
    @ObservationIgnored private var pushFlushTask: Task<Void, Never>?

    /// While the popover is visible, every watchlist symbol served by a streaming source
    /// ticks live; the rest keep their source's poll cadence. Closing the popover
    /// unsubscribes — the menu bar text is fine at poll granularity.
    func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        watchlistStreamTask?.cancel()
        watchlistStreamTask = nil
        watchlistStreamSessionID = nil
        // Keep the last known/expected streaming state while the popover disappears.
        // Resetting it here makes the still-visible closing frame flash "quotes healthy".
        guard visible else { return }
        restartWatchlistStream()
    }

    /// Re-subscribes after watchlist edits while the popover is open.
    func watchlistSymbolsChanged() {
        guard isPopoverVisible else { return }
        restartWatchlistStream()
    }

    /// True while a configured live source is being connected or actively delivering.
    /// Deliberate popover lifecycle cancellations keep this stable to avoid status flicker;
    /// unsupported configuration and unexpected stream termination reset it.
    private(set) var liveStreaming = false

    private func restartWatchlistStream() {
        watchlistStreamTask?.cancel()
        watchlistStreamTask = nil
        watchlistStreamSessionID = nil
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
        providerDescriptors.contains { descriptor in
            descriptor.capabilities.contains(.streaming)
                && isProviderEnabled(descriptor.id)
                && (descriptor.id != LongbridgeProvider.providerID || longbridgeConfigured)
                && symbols.contains { descriptor.supports(.streaming, in: $0.market) }
        }
    }

    /// Pushes arrive per tick and per symbol; flushing them through a short buffer keeps a
    /// busy market from re-rendering the list dozens of times per second. Detail-page
    /// streams feed the same buffer so every push path shares the coalescing and gating.
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

    /// An open NSMenu (sort submenu, poll-interval picker, row context menu…) cannot survive
    /// its host view being re-rendered every 250ms, so store writes hold while any menu
    /// tracks; the buffer keeps absorbing ticks and flushes the moment tracking ends.
    private func flushPendingPushes() {
        guard menuTrackingDepth == 0, !pendingPushes.isEmpty else { return }
        let batch = Array(pendingPushes.values)
        pendingPushes = [:]
        market.applyStreamed(batch)
    }

    @ObservationIgnored private var menuTrackingDepth = 0

    private func observeMenuTracking() {
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTrackingDepth += 1 }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
                self.flushPendingPushes()
            }
        }
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
