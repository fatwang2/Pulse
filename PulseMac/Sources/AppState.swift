import AppKit
import Foundation
import Observation
import OSLog
import PulseCore
import PulseUI

@MainActor
@Observable
final class AppState {
    private static let longbridgeLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.pulse.mac",
        category: "LongbridgeAccess"
    )
    private static let longbridgeAccessSnapshotKey = "pulse.longbridge.quoteAccess.v1"

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
    private(set) var longbridgeConnectionStatus: LongbridgeConnectionStatus = .disconnected
    private(set) var longbridgeQuoteAccess: [Market: LongbridgeQuoteAccess] = [:]
    private(set) var longbridgeDelayedMarkets: Set<Market> = []
    private(set) var longbridgeDowngradedMarkets: Set<Market> = []
    /// OAuth client id of the stored authorization, shown in settings so the user can
    /// match this install against Longbridge's authorization-management list before
    /// revoking anything there.
    private(set) var longbridgeOAuthClientID: String?
    var longbridgeHasDelayedQuoteAccess: Bool { !longbridgeDelayedMarkets.isEmpty }
    var longbridgeNeedsAuthorizationRefresh: Bool {
        longbridgeAuthState == .oauth && longbridgeHasDelayedQuoteAccess
    }
    @ObservationIgnored private var isUpdatingLongbridgeAuth = false

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
        let provider = CompositeProvider(providers: [longbridge, binance, TencentProvider(), NaverProvider(), YahooProvider(), SinaProvider(),
                                                     ShanghaiGoldExchangeProvider(), EastmoneyProvider()],
                                         disabledIDs: disabledIDs)
        self.settings = settings
        self.watchlist = watchlist
        self.market = market
        self.provider = provider
        self.binance = binance
        self.longbridge = longbridge
        self.longbridgeAuthState = authState
        self.longbridgeOAuthClientID = authState == .oauth
            ? LongbridgeCredentialStore.loadOAuthTokens()?.clientID
            : nil
        // Distinct registration names keep the two clients tellable-apart in
        // Longbridge's authorization-management list; a user once revoked the active
        // production grant because both entries were just called "Pulse". Existing
        // registrations keep their original name until they re-register.
        self.longbridgeOAuth = LongbridgeOAuthAuthenticator(
            redirectScheme: Bundle.main.bundleIdentifier ?? "app.pulse.mac",
            clientName: Bundle.main.bundleIdentifier == "app.pulse.mac.dev" ? "Pulse Dev" : "Pulse"
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
        Task { [weak self, longbridge] in
            let updates = await longbridge.connectionStatusUpdates()
            for await status in updates {
                guard let self else { return }
                self.longbridgeConnectionStatus = status
                if status == .connected, !self.isUpdatingLongbridgeAuth {
                    await self.refreshLongbridgeQuoteAccess()
                }
            }
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
        if !enabled, id == LongbridgeProvider.providerID {
            Task { await longbridge.resetConnection() }
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
            if isAnyHostVisible { restartWatchlistStream() }
        }
    }

    // MARK: - Longbridge auth

    /// Runs the browser OAuth flow end to end: authorize → validate against the live
    /// gateway → persist. A failed attempt rolls back to whatever auth was active before.
    func connectLongbridgeOAuth() async throws {
        let tokens = try await longbridgeOAuth.authorize { url in
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        isUpdatingLongbridgeAuth = true
        defer { isUpdatingLongbridgeAuth = false }
        try await activate(auth: .oauth(Self.makeOAuthSession(tokens)))
        try LongbridgeCredentialStore.saveOAuthTokens(tokens)
        LongbridgeCredentialStore.clear() // OAuth replaces any pasted API-key credentials
        longbridgeAuthState = .oauth
        longbridgeOAuthClientID = tokens.clientID
        // Connecting is the strongest possible "turn this on" signal — flip the
        // switch that was locked off while unconfigured.
        setProvider(LongbridgeProvider.providerID, enabled: true)
        await refreshLongbridgeQuoteAccess()
    }

    /// Forwards `bundleid://oauth/callback?...` URLs from the system to the pending flow.
    func handleOAuthCallback(_ url: URL) {
        Task { _ = await longbridgeOAuth.handleCallback(url) }
    }

    /// Validates against the live gateway before persisting; invalid credentials are rolled
    /// back so a previously working configuration is never destroyed by a failed edit.
    func saveLongbridgeCredentials(_ credentials: LongbridgeCredentials) async throws {
        isUpdatingLongbridgeAuth = true
        defer { isUpdatingLongbridgeAuth = false }
        try await activate(auth: .apiKey(credentials))
        try LongbridgeCredentialStore.save(credentials)
        LongbridgeCredentialStore.clearOAuthTokens() // manual credentials replace OAuth
        longbridgeAuthState = .apiKey
        longbridgeOAuthClientID = nil
        setProvider(LongbridgeProvider.providerID, enabled: true)
        await refreshLongbridgeQuoteAccess()
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
        longbridgeQuoteAccess = [:]
        longbridgeDelayedMarkets = []
        longbridgeDowngradedMarkets = []
        longbridgeOAuthClientID = nil
        Task {
            await longbridge.updateAuth(nil)
        }
        applyProviderAvailability()
    }

    /// Retries only the market-data transport. OAuth credentials stay intact, and the
    /// provider's circuit breaker is cleared so the request is not delayed by cooldown.
    func retryLongbridgeConnection() {
        guard longbridgeConfigured, isProviderEnabled(LongbridgeProvider.providerID) else { return }
        Task {
            await longbridge.resetConnection()
            await provider.resetHealth(LongbridgeProvider.providerID)
            engine.poke()
            if isAnyHostVisible { restartWatchlistStream() }
        }
    }

    /// Reads the package list from the live SDK context and remembers the best
    /// access previously negotiated by this OAuth client. A downgrade is surfaced
    /// to the user but never destroys credentials or starts OAuth automatically.
    private func refreshLongbridgeQuoteAccess() async {
        guard longbridgeConfigured else { return }
        do {
            let packages = try await longbridge.quotePackages()
            guard !packages.isEmpty else { return }

            let markets: [Market] = [.us, .hk, .sh, .sz]
            let current = Dictionary(uniqueKeysWithValues: markets.map {
                ($0, LongbridgeProvider.quoteAccess(for: $0, packages: packages))
            })
            longbridgeQuoteAccess = current
            longbridgeDelayedMarkets = Set(current.compactMap { market, access in
                access == .delayed ? market : nil
            })

            let packageKeys = packages.map(\.key).filter { !$0.isEmpty }.sorted()
            guard let fingerprint = LongbridgeCredentialStore.loadOAuthTokens()?.clientFingerprint else {
                longbridgeDowngradedMarkets = []
                Self.longbridgeLogger.notice(
                    "Quote access packages=\(packageKeys.joined(separator: ","), privacy: .public) auth=api-key"
                )
                return
            }

            let prior = Self.loadLongbridgeAccessSnapshot()
            let priorAccess = prior?.clientFingerprint == fingerprint ? prior?.bestAccess ?? [:] : [:]
            longbridgeDowngradedMarkets = Set(markets.filter {
                priorAccess[$0.rawValue] == .realtime && current[$0] == .delayed
            })

            var bestAccess = priorAccess
            for (market, access) in current where access != .unknown {
                if access == .realtime || bestAccess[market.rawValue] == nil {
                    bestAccess[market.rawValue] = access
                }
            }
            Self.saveLongbridgeAccessSnapshot(LongbridgeAccessSnapshot(
                clientFingerprint: fingerprint,
                bestAccess: bestAccess,
                packageKeys: packageKeys,
                observedAt: .now
            ))

            let accessSummary = markets
                .map { "\($0.rawValue)=\(current[$0]?.rawValue ?? "unknown")" }
                .joined(separator: ",")
            Self.longbridgeLogger.notice(
                "Quote access client=\(fingerprint, privacy: .public) packages=\(packageKeys.joined(separator: ","), privacy: .public) access=\(accessSummary, privacy: .public)"
            )
            if !longbridgeDowngradedMarkets.isEmpty {
                let markets = longbridgeDowngradedMarkets.map(\.rawValue).sorted().joined(separator: ",")
                Self.longbridgeLogger.error(
                    "Quote entitlement downgrade client=\(fingerprint, privacy: .public) markets=\(markets, privacy: .public)"
                )
            }
        } catch {
            Self.longbridgeLogger.error(
                "Quote access inspection failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private struct LongbridgeAccessSnapshot: Codable {
        var clientFingerprint: String
        var bestAccess: [String: LongbridgeQuoteAccess]
        var packageKeys: [String]
        var observedAt: Date
    }

    private static func loadLongbridgeAccessSnapshot() -> LongbridgeAccessSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: longbridgeAccessSnapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(LongbridgeAccessSnapshot.self, from: data)
    }

    private static func saveLongbridgeAccessSnapshot(_ snapshot: LongbridgeAccessSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: longbridgeAccessSnapshotKey)
    }

    // MARK: - Menu bar text

    var menuBarItem: WatchItem? {
        switch settings.menuBarMode {
        case .compact:
            return nil
        case .single:
            let items = watchlist.allItems
            guard !items.isEmpty else { return nil }
            if let primary = settings.primarySymbol,
               let item = items.first(where: { $0.symbol == primary }) {
                return item
            }
            return items.first
        case .rotate:
            let items = watchlist.items(in: menuBarRotationGroupID)
            guard !items.isEmpty else { return nil }
            return items[rotationIndex % items.count]
        }
    }

    var menuBarRotationGroupID: UUID? {
        if let id = settings.rotateGroupID, watchlist.group(for: id) != nil { return id }
        return watchlist.groups.first?.id
    }

    func setMenuBarRotationGroup(_ id: UUID) {
        guard watchlist.group(for: id) != nil else { return }
        settings.rotateGroupID = id
        rotationIndex = 0
    }

    func watchlistGroupsChanged() {
        if settings.rotateGroupID != menuBarRotationGroupID {
            settings.rotateGroupID = menuBarRotationGroupID
        }
        rotationIndex = 0
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

    /// One presentation name per instrument, independent of whichever provider
    /// currently supplies its price. Quote names remain source metadata only.
    func displayName(for symbol: SymbolID) -> String {
        if let item = watchlist.item(for: symbol) {
            return item.resolvedDisplayName
        }
        if let index = symbol.indexID {
            return index.displayName
        }
        return market.quote(for: symbol)?.name ?? symbol.displayCode
    }

    /// Calculated benchmarks, not traded securities: catalog indices carry an
    /// `indexID`; search-classified ones rely on the stored instrument type.
    func isIndex(_ symbol: SymbolID) -> Bool {
        symbol.indexID != nil || watchlist.item(for: symbol)?.resolvedInstrumentType == .index
    }

    /// The US pre/post setting only applies to instruments that trade those
    /// sessions. Indices (NASDAQ Composite, S&P 500, …) compute during regular
    /// hours only, so their charts never get extended-hours wings.
    func showsExtendedHours(for symbol: SymbolID) -> Bool {
        settings.showsUSExtendedHours && symbol.market == .us && !isIndex(symbol)
    }

    private func shortName(for item: WatchItem) -> String {
        // US stocks use the ticker (AAPL is shorter than "Apple Inc."); Chinese names are truncated to the first 5 characters
        if item.symbol.market == .us { return item.symbol.code }
        return String(item.resolvedDisplayName.prefix(5))
    }

    // MARK: - Rotation

    private func startRotation() {
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.settings.rotateInterval ?? 6
                try? await Task.sleep(for: .seconds(interval))
                guard let self, self.settings.menuBarMode == .rotate else { continue }
                let count = self.watchlist.items(in: self.menuBarRotationGroupID).count
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
    @ObservationIgnored private var visibleHosts: Set<PulseHost> = []
    @ObservationIgnored private var pendingPushes: [SymbolID: Quote] = [:]
    @ObservationIgnored private var pushFlushTask: Task<Void, Never>?

    private var isAnyHostVisible: Bool { !visibleHosts.isEmpty }

    /// While the watchlist is on screen, every symbol served by a streaming source ticks
    /// live; the rest keep their source's poll cadence. Nothing on screen unsubscribes —
    /// the menu bar text is fine at poll granularity.
    ///
    /// The panel and the pinned window are independent hosts that can overlap, so the
    /// subscription follows whether *any* of them is showing rather than the last one to
    /// report. Only the transitions matter: a host appearing while another is already
    /// visible must not tear down and rebuild a healthy stream.
    func setHostVisible(_ host: PulseHost, _ visible: Bool) {
        let wasVisible = isAnyHostVisible
        if visible {
            visibleHosts.insert(host)
        } else {
            visibleHosts.remove(host)
        }
        guard wasVisible != isAnyHostVisible else { return }

        // The reorder UI cannot outlive its host; if it was active on close,
        // release the quote hold so the menu bar keeps updating.
        if !isAnyHostVisible { setUserReordering(false) }
        watchlistStreamTask?.cancel()
        watchlistStreamTask = nil
        watchlistStreamSessionID = nil
        // Keep the last known/expected streaming state while the host disappears.
        // Resetting it here makes the still-visible closing frame flash "quotes healthy".
        guard isAnyHostVisible else { return }
        restartWatchlistStream()
    }

    /// Re-subscribes after watchlist edits while the watchlist is on screen.
    func watchlistSymbolsChanged() {
        guard isAnyHostVisible else { return }
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
        guard menuTrackingDepth == 0, !isUserReordering, !pendingPushes.isEmpty else { return }
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
            watchlist.upgradeDisplayName(
                for: quote.symbol,
                to: name,
                source: source
            )
        }
    }

    @ObservationIgnored private var menuTrackingDepth = 0
    @ObservationIgnored private var isUserReordering = false

    /// Drag-to-reorder shares the NSMenu constraint: the AppKit drag session (and its
    /// drop indicator) dies the moment the host rows re-render under it. While the
    /// reorder UI is active every quote path holds — pushes keep buffering above, the
    /// polling engine skips applying — and both catch up the moment the mode ends.
    func setUserReordering(_ active: Bool) {
        guard isUserReordering != active else { return }
        isUserReordering = active
        engine.writesHeld = active
        if !active { flushPendingPushes() }
    }

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

    /// How often a realtime price actually refreshes, for sources Pulse polls.
    /// Nil for pushing sources — there "realtime" already says it — and nil when
    /// the source is delayed, since that number is the one that matters then.
    func quoteCadenceText(for quote: Quote) -> String? {
        guard quoteDelay(for: quote) == 0,
              let sourceID = quote.sourceID,
              let descriptor = providerDescriptors.first(where: { $0.id == sourceID }),
              let seconds = descriptor.pollingCadenceSeconds(interval: pollInterval(for: sourceID))
        else { return nil }
        return PulseLocalization.localizedString("quote.cadence.seconds", seconds)
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
