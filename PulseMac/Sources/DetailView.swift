import SwiftUI
import PulseCore
import PulseUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseHost) private var host
    let symbol: SymbolID
    @Binding var route: PopoverRoute

    @State private var period: CandlePeriod = .minute1
    @State private var candles: [Candle] = []
    /// What `candles` hold, and by the same token which request they answer for.
    /// A switch leaves the previous period's bars in place for a moment; they
    /// must neither be drawn under the new period's axis nor counted as its
    /// answer. Only once this matches the request on screen does an empty
    /// `candles` mean the source had nothing.
    @State private var candlesKey: CandleCacheKey?
    @State private var isLoading = false
    @State private var isFirstLoad = true
    @State private var shareFeedback: ShareFeedback?
    /// Owned here (not in the chart) so sharing can read the zoomed candle window.
    @State private var candleViewport = CandleChartViewport()

    private static let minutePeriods: [CandlePeriod] = [
        .minute5, .minute15, .minute30, .hour1,
    ]

    // Page flow: price hero → trend chart → market stats → position.
    // Source/time/delay metadata sits at the hero's top-right corner, annotating the price.
    var body: some View {
        VStack(spacing: 0) {
            heroSection
            sectionSeparator
            chartSection
            sectionSeparator
            statsSection
            positionArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollEdgeEffectStyle(.soft, for: .all)
        // Navigation and instrument identity belong to the page, not the window.
        // Keeping this row inline also aligns it with the pinned watchlist's first
        // content row instead of squeezing a long name between the traffic lights
        // and the title-bar actions.
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar {
            if host == .pinnedWindow {
                ToolbarSpacer(.flexible)
                ToolbarItemGroup(placement: .primaryAction) {
                    toolbarActions
                }
            }
        }
        .onAppear { maybeOfferKlineTourStep() }
        .onDisappear {
            // Leaving with the candle bubble up counts as the step seen; the pin
            // stop then presents back on the list. An offer that never fired
            // stays pending for the next detail visit.
            if appState.onboarding.activeTourStep == .kline {
                appState.onboarding.completeStep(.kline)
            }
        }
        // Any period switch is the lesson learned, daily or not.
        .onChange(of: period) { _, _ in
            appState.onboarding.completeStep(.kline)
        }
        // Real-time push while the page is on screen: each tick lands in the store, and the
        // price / market-time views animate through their existing transitions. Closing the
        // page cancels the task, which unsubscribes upstream; polling remains the fallback.
        .task(id: symbol) {
            guard let stream = appState.provider.quoteStream(for: [symbol]) else { return }
            do {
                for try await quote in stream {
                    appState.ingestStreamedQuote(quote)
                }
            } catch {
                // Stream dropped (e.g. socket reconnect) — the 15s polling loop still updates the page.
            }
        }
        // Symbols opened from search aren't in the watchlist, so the engine's polling
        // loop never covers them; the page runs its own light poll until it closes
        // (or the symbol gets added, at which point the engine takes over).
        .task(id: symbol) {
            while !Task.isCancelled {
                if appState.watchlist.item(for: symbol) == nil {
                    if let quote = try? await appState.provider.quotes(for: [symbol]).first {
                        appState.ingestStreamedQuote(quote)
                    }
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .task(id: chartRequest) {
            let request = chartRequest
            let taskStart = ContinuousClock.now
            // Switching periods repaints from whatever is already cached for the
            // new one, however old, and the refresh replaces it in place — the
            // chart never has to blank out to change resolution. The first load
            // skips this: its render would land mid-push (see the clearance below).
            if !isFirstLoad,
               let cached = appState.market.cachedCandles(for: request, maxAge: .infinity),
               !cached.isEmpty {
                candles = cached
                candlesKey = request
            }
            // Show the spinner only when loading is actually slow: a sub-150ms load
            // (cache hit) swaps silently instead of flashing a progress indicator.
            let spinnerDelay = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                isLoading = true
            }
            defer {
                spinnerDelay.cancel()
                isLoading = false
            }
            let loaded = await appState.engine.loadCandles(
                for: request.symbol, period: request.period,
                count: candleCount(for: request.period)
            )
            if isFirstLoad {
                // The first load starts while the push transition is still running,
                // and Swift Charts' first render is expensive (up to 1440 intraday
                // points) — hold a fast (cached) result until the slide has settled.
                let clearance: Duration = .milliseconds(350)
                let elapsed = taskStart.duration(to: .now)
                if elapsed < clearance {
                    try? await Task.sleep(for: clearance - elapsed)
                }
                isFirstLoad = false
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                candles = loaded
                candlesKey = request
            }
        }
    }

    /// Symbol + period identify a chart load: the page is reused across symbols,
    /// so a reload owes itself to either changing.
    private var chartRequest: CandleCacheKey {
        CandleCacheKey(symbol: symbol, period: period)
    }

    private var quote: Quote? { appState.market.quote(for: symbol) }
    private var item: WatchItem? { appState.watchlist.item(for: symbol) }

    private var currencyCode: String? {
        quote?.currencyCode ?? symbol.currencyCode
    }

    /// K-line periods load history behind the zoomable window (the chart shows the latest
    /// ~60 bars by default). Intraday resolutions retain enough bars to pan backward while
    /// staying inside Longbridge/Binance's 1,000-candle request ceiling.
    private func candleCount(for period: CandlePeriod) -> Int {
        switch period {
        case .minute5, .minute15, .minute30, .hour1:
            guard let minutes = period.intradayMinutes else { return 240 }
            let sessionMinutes = switch symbol.market {
            case .sh, .sz: 240
            case .hk: 330
            // Providers fetch all sessions; the presentation setting filters to
            // regular hours or 04:00–20:00 ET without a second request.
            case .us: 16 * 60
            case .crypto: 24 * 60
            case .metal: 23 * 60
            case .metalCN: 780
            case .jp: 330
            case .kr, .kq: 390
            }
            let historyDays = switch symbol.market {
            case .crypto, .metal: 1
            case .us, .hk, .sh, .sz, .metalCN, .jp, .kr, .kq: 5
            }
            return min(max(sessionMinutes / minutes * historyDays, 240), 1_000)
        case .day: return 250
        case .week: return 260
        case .month: return 240
        case .minute1:
            return IntradayTrendSnapshot.recommendedCandleCount(for: symbol.market)
        }
    }

    /// Only bars that belong to what is on screen now. Everything the chart
    /// draws goes through here, so a pending switch shows its own loading state
    /// rather than the outgoing period's data.
    private var sourceCandles: [Candle] {
        if candlesKey == chartRequest { return candles }
        // The reload task lands a frame later than the switch itself. Painting
        // the cache here rather than waiting for it closes that frame, so going
        // back to a period already loaded once never blanks at all.
        guard !isFirstLoad else { return [] }
        return appState.market.cachedCandles(for: chartRequest, maxAge: .infinity) ?? []
    }

    /// Minute K data is fetched with all US sessions so the setting can switch instantly.
    /// This also removes overnight bars: Pulse's setting promises pre/post, not 24-hour US trading.
    private var chartCandles: [Candle] {
        guard period.isMinuteK else { return sourceCandles }
        return IntradayTradingSession.filterCandles(
            sourceCandles,
            market: symbol.market,
            includesExtendedHours: appState.showsExtendedHours(for: symbol)
        )
    }

    // MARK: - Chrome

    private var backButton: some View {
        IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.backHelp")) {
            route = .list
        }
    }

    private var titleCluster: some View {
        HStack(spacing: 6) {
            Text(appState.displayName(for: symbol))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            MarketBadge(market: symbol.market)
                .fixedSize()
            Text(symbol.displayCode)
                .font(.system(size: 10).monospaced())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            backButton
            titleCluster
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            if host == .menuBar {
                headerActions
            }
        }
        .overlay(alignment: .trailing) {
            if let shareFeedback {
                ShareFeedbackHUD(feedback: shareFeedback)
                    .padding(.trailing, host == .pinnedWindow ? 10 : (item?.supportsPosition == true ? 58 : 30))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        // A standalone page header needs the panel's full inset, while the
        // pinned window already has a title bar immediately above it.
        .padding(.top, host == .pinnedWindow ? 2 : 7)
        .padding(.bottom, 7)
    }

    private var shareMenu: some View {
        ClusterMenu(
            systemName: "square.and.arrow.up",
            help: PulseLocalization.localizedString("action.share")
        ) {
            Button {
                copyShareImage()
            } label: {
                Label(
                    PulseLocalization.localizedString("action.copyAsImage"),
                    systemImage: "photo"
                )
            }
            .disabled(quote == nil || chartCandles.isEmpty)
            Button {
                copyShareText()
            } label: {
                Label(
                    PulseLocalization.localizedString("action.copyAsText"),
                    systemImage: "doc.text"
                )
            }
            .disabled(quote == nil)
        }
        .disabled(quote == nil)
        .opacity(quote == nil ? 0.45 : 1)
    }

    // MARK: - Onboarding tour

    /// Next on this stop performs the switch itself. The bubble goes first and
    /// the chart swaps a beat later, so the popover's dismissal never overlaps
    /// the content change — same sequencing as the list page's action steps.
    private var klineTourBubble: OnboardingTourBubble {
        OnboardingTourBubble(
            step: .kline,
            text: PulseLocalization.localizedString("onboarding.tour.kline")
        ) {
            appState.onboarding.completeStep(.kline)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                period = .day
            }
        }
    }

    /// Same election as the list page: the pinned window carries the tour while
    /// it is up, else the panel does.
    private var isTourHost: Bool {
        host == .pinnedWindow || !appState.settings.pinnedWindowVisible
    }

    private var klineTourBinding: Binding<Bool> {
        Binding(
            get: { isTourHost && appState.onboarding.activeTourStep == .kline },
            set: { presented in
                if !presented, appState.onboarding.activeTourStep == .kline {
                    appState.onboarding.pauseTour()
                }
            }
        )
    }

    /// Offers the candle stop once this page settles; the stop was queued by the
    /// detail step completing on the way in.
    private func maybeOfferKlineTourStep() {
        guard isTourHost,
              appState.onboarding.tourAvailable,
              appState.onboarding.activeTourStep == nil,
              appState.onboarding.tourResumeStep == .kline else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard isTourHost,
                  appState.onboarding.tourAvailable,
                  appState.onboarding.activeTourStep == nil,
                  appState.onboarding.tourResumeStep == .kline else { return }
            appState.onboarding.beginTourIfNeeded()
        }
    }

    /// Opened from search without being watched: offer the add here so a lookup can
    /// graduate into the list without going back.
    private var addButton: some View {
        ClusterIcon(
            systemName: "plus",
            help: PulseLocalization.localizedString(
                "search.addToGroup",
                appState.watchlist.selectedGroup?.name ?? ""
            )
        ) {
            addToWatchlist()
        }
    }

    @ViewBuilder private func positionButton(_ item: WatchItem) -> some View {
        ClusterIcon(
            systemName: item.hasPosition ? "briefcase.fill" : "briefcase",
            help: item.hasPosition
                ? PulseLocalization.localizedString("action.editPosition")
                : PulseLocalization.localizedString("action.addPosition")
        ) {
            route = .position(item.symbol, .detail(symbol))
        }
    }

    @ViewBuilder private var headerActions: some View {
        shareMenu
        if item == nil {
            addButton
        }
        if let item, item.supportsPosition {
            positionButton(item)
        }
    }

    /// The pinned window's title bar carries only page-level actions. Navigation and
    /// instrument identity stay in the page header below, where long names have room.
    @ViewBuilder private var toolbarActions: some View {
        Menu {
            Button {
                copyShareImage()
            } label: {
                Label(
                    PulseLocalization.localizedString("action.copyAsImage"),
                    systemImage: "photo"
                )
            }
            .disabled(quote == nil || chartCandles.isEmpty)
            Button {
                copyShareText()
            } label: {
                Label(
                    PulseLocalization.localizedString("action.copyAsText"),
                    systemImage: "doc.text"
                )
            }
            .disabled(quote == nil)
        } label: {
            Label(
                PulseLocalization.localizedString("action.share"),
                systemImage: "square.and.arrow.up"
            )
        }
        .menuIndicator(.hidden)
        .help(PulseLocalization.localizedString("action.share"))
        .disabled(quote == nil)

        if item == nil {
            Button {
                addToWatchlist()
            } label: {
                Label(
                    PulseLocalization.localizedString(
                        "search.addToGroup",
                        appState.watchlist.selectedGroup?.name ?? ""
                    ),
                    systemImage: "plus"
                )
            }
            .help(PulseLocalization.localizedString(
                "search.addToGroup",
                appState.watchlist.selectedGroup?.name ?? ""
            ))
        }

        if let item, item.supportsPosition {
            Button {
                route = .position(item.symbol, .detail(symbol))
            } label: {
                Label(
                    item.hasPosition
                        ? PulseLocalization.localizedString("action.editPosition")
                        : PulseLocalization.localizedString("action.addPosition"),
                    systemImage: item.hasPosition ? "briefcase.fill" : "briefcase"
                )
            }
            .help(item.hasPosition
                ? PulseLocalization.localizedString("action.editPosition")
                : PulseLocalization.localizedString("action.addPosition"))
        }
    }

    @MainActor
    private func addToWatchlist() {
        let info = SymbolInfo(
            symbol: symbol,
            name: appState.market.quote(for: symbol)?.name ?? appState.displayName(for: symbol)
        )
        appState.watchlist.add(info)
        appState.engine.poke()
    }

    @MainActor
    private var sharedCandles: [Candle] {
        // K-line exports use exactly the zoomed window on screen; the intraday
        // chart keeps the full session, whose frame is its own context.
        let allCandles = chartCandles
        if period == .minute1 {
            return IntradayTrendSnapshot(
                candles: allCandles,
                market: symbol.market,
                includesExtendedHours: appState.showsExtendedHours(for: symbol)
            ).candles
        }
        return Array(allCandles[candleViewport.visibleRange(dataCount: allCandles.count)])
    }

    private var sharedInstrumentType: InstrumentType? {
        if let type = item?.resolvedInstrumentType { return type }
        if symbol.indexID != nil { return .index }
        if symbol.metalID != nil { return .commodity }
        if symbol.cryptoPair != nil { return .crypto }
        return nil
    }

    @MainActor
    private func copyShareImage() {
        do {
            let snapshot = DetailShareSnapshot(
                appState: appState,
                symbol: symbol,
                period: period,
                candles: sharedCandles
            )
            let palette = ChangePalette(redUp: snapshot.redUp)
            let card = PulseShareCard(
                ambientColor: snapshot.changeValue.map(palette.color(for:))
            ) {
                DetailShareContent(snapshot: snapshot)
            }
            let artifact = try ShareImageRenderer.render(
                card,
                configuration: .detailLandscape(
                    colorScheme: colorScheme,
                    locale: appState.settings.locale
                )
            )
            try ClipboardImageExporter.write(artifact)
            showShareFeedback(content: .image, isSuccess: true)
        } catch {
            showShareFeedback(content: .image, isSuccess: false)
        }
    }

    @MainActor
    private func copyShareText() {
        guard let quote else {
            showShareFeedback(content: .text, isSuccess: false)
            return
        }
        do {
            let snapshot = DetailTextSnapshot(
                symbol: symbol,
                name: appState.displayName(for: symbol),
                instrumentType: sharedInstrumentType,
                quote: quote,
                period: period,
                candles: sharedCandles,
                includesExtendedHours: appState.showsExtendedHours(for: symbol)
            )
            try ClipboardTextExporter.write(snapshot.renderedText())
            showShareFeedback(content: .text, isSuccess: true)
        } catch {
            showShareFeedback(content: .text, isSuccess: false)
        }
    }

    @MainActor
    private func showShareFeedback(content: ShareFeedback.Content, isSuccess: Bool) {
        let feedback = ShareFeedback(content: content, isSuccess: isSuccess)
        withAnimation(.snappy(duration: 0.2)) {
            shareFeedback = feedback
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(isSuccess ? 1.5 : 3))
            guard shareFeedback?.id == feedback.id else { return }
            withAnimation(.snappy(duration: 0.2)) {
                shareFeedback = nil
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let quote {
                    let color = appState.palette.color(for: quote.change)
                    Text(quotePriceLabel(for: quote))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(PriceFormatter.price(quote.price, market: symbol.market))
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .foregroundStyle(color)
                            // Animate the same magnitude the string prints so a third
                            // decimal the market allows stays in sync with the transition.
                            .contentTransition(
                                reduceMotion
                                    ? .opacity
                                    : .numericText(value: PriceFormatter.animatablePrice(
                                        quote.price,
                                        market: symbol.market
                                    ))
                            )
                            .animation(
                                .snappy(duration: 0.25),
                                value: PriceFormatter.animatablePrice(quote.price, market: symbol.market)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if let currency = quote.currencyCode {
                            Text(currency)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(PriceFormatter.change(quote.change, market: symbol.market))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                        Text(PriceFormatter.percent(quote.changePercent))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(color)
                    if let regularClose = regularCloseDisplay(for: quote) {
                        regularCloseRow(regularClose)
                            .padding(.top, 3)
                    }
                } else {
                    Text(PulseLocalization.localizedString("quote.price.current"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("—")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            // The column is bottom-aligned to the price, so it grows upward:
            // the summary link goes on top, where arriving late pushes nothing
            // that was already there.
            VStack(alignment: .trailing, spacing: 6) {
                if symbol.isDescribable {
                    aboutLink
                }
                if let quote {
                    quoteMeta(for: quote)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// The way into the business summary. It lives in the hero's annotation
    /// corner rather than as a block of text on the page: the summary is long,
    /// and a page whose quote already moves under the reader can't afford a
    /// late arrival reflowing it. Nothing is fetched to show this — the link is
    /// there for anything that could have a summary, and the page it opens does
    /// the asking.
    private var aboutLink: some View {
        Button {
            route = .profile(symbol)
        } label: {
            HStack(spacing: 2) {
                Text(PulseLocalization.localizedString("detail.section.about"))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .semibold))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// Quote provenance at the hero's top-right: freshness, source, then market-time basis.
    /// Bottom-aligns with the price block so the metadata reads as an annotation to the quote.
    private func quoteMeta(for quote: Quote) -> some View {
        let delayText = appState.quoteDelayText(for: quote)
        // A polled source is current but steps; saying so next to "realtime"
        // keeps the word honest without spending another line.
        let freshness = [delayText ?? PulseLocalization.localizedString("quote.realtime"),
                         appState.quoteCadenceText(for: quote)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(delayText == nil ? Color.green.opacity(0.8) : .orange)
                    .frame(width: 5, height: 5)
                Text(freshness)
                    .foregroundStyle(delayText == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange.opacity(0.85)))
            }
            if let sourceName = quote.sourceName {
                Text(sourceName)
                    .foregroundStyle(.tertiary)
            }
            Text(appState.quoteMarketTimeText(for: quote))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                // Market time ticks with real-time pushes; roll the digits like the price does.
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(.snappy(duration: 0.25), value: quote.timestamp)
        }
        .font(.system(size: 9, weight: .medium))
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .allowsTightening(true)
        .frame(maxWidth: 132, alignment: .trailing)
    }

    /// The last regular session's result, shown under the live extended-session
    /// price. Pre-market labels it "昨收" (that close was yesterday's); post and
    /// overnight label it "收盘" (today's just-finished session). During regular
    /// hours there is no "yesterday" to show and the row disappears.
    private func regularCloseDisplay(for quote: Quote) -> (label: String, close: Quote.RegularSessionClose)? {
        guard let regularSession = quote.regularSession else { return nil }
        switch quote.marketState {
        case .preMarket:
            return (PulseLocalization.localizedString("quote.regularClose.previous"), regularSession)
        case .postMarket, .overnight:
            return (PulseLocalization.localizedString("quote.regularClose.today"), regularSession)
        case .regular, .closed, .none:
            return nil
        }
    }

    private func regularCloseRow(_ display: (label: String, close: Quote.RegularSessionClose)) -> some View {
        let close = display.close
        let color = close.change.map { appState.palette.color(for: $0) }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(display.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(PriceFormatter.price(close.price, market: symbol.market))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color ?? .secondary)
            if let change = close.change, let percent = close.changePercent {
                Text(PriceFormatter.change(change, market: symbol.market))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(color ?? .secondary)
                Text(PriceFormatter.percent(percent))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color ?? .secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .allowsTightening(true)
    }

    private func quotePriceLabel(for quote: Quote) -> String {
        switch quote.marketState {
        case .preMarket:
            PulseLocalization.localizedString("quote.price.preMarket")
        case .postMarket:
            PulseLocalization.localizedString("quote.price.postMarket")
        case .overnight:
            PulseLocalization.localizedString("quote.price.overnight")
        case .closed:
            PulseLocalization.localizedString("quote.price.close")
        case .regular, .none:
            PulseLocalization.localizedString("quote.price.current")
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(spacing: 7) {
            chartHeader
            .padding(.horizontal, 12)
            // Leading 10 + the intraday plot's own 2pt inset lands the plot edge on the 12pt text grid;
            // trailing 12 aligns the y-axis labels with it directly.
            chart
                .padding(.leading, 10)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Keeps the period control compact when its labels fit, then gives it a full row for
    /// longer localizations instead of clipping or shrinking the text beyond readability.
    private var chartHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sectionHeaderText(PulseLocalization.localizedString("detail.section.trend"))
                Spacer(minLength: 0)
                picker
                    .frame(width: 260)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionHeaderText(PulseLocalization.localizedString("detail.section.trend"))
                picker
            }
        }
    }

    private var picker: some View {
        HStack(spacing: 4) {
            periodButton(.minute1)
            minutePeriodMenu
            periodButton(.day)
                .popover(isPresented: klineTourBinding, arrowEdge: .bottom) {
                    klineTourBubble
                }
            periodButton(.week)
            periodButton(.month)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PulseLocalization.localizedString("detail.period"))
    }

    private func periodButton(_ value: CandlePeriod) -> some View {
        Button {
            period = value
        } label: {
            periodControlLabel(value.displayName, isSelected: period == value)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(value.displayName)
        .accessibilityAddTraits(period == value ? .isSelected : [])
    }

    private var minutePeriodMenu: some View {
        let selected = appState.settings.minuteCandlePeriod.isMinuteK
            ? appState.settings.minuteCandlePeriod
            : CandlePeriod.minute5
        return HStack(spacing: 0) {
            // Main segment action: return to the last chosen minute resolution.
            Button {
                period = selected
            } label: {
                Text(selected.displayName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .help(selected.displayName)
            .accessibilityAddTraits(period.isMinuteK ? .isSelected : [])

            // Secondary action: only the small trailing chevron opens the resolution menu.
            Menu {
                ForEach(Self.minutePeriods, id: \.self) { value in
                    Button {
                        appState.settings.minuteCandlePeriod = value
                        period = value
                    } label: {
                        if value == selected {
                            Label(value.displayName, systemImage: "checkmark")
                        } else {
                            Text(value.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 5.5, weight: .semibold))
                    .frame(width: 18, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(selected.displayName)
        }
        .font(.system(size: 9, weight: period.isMinuteK ? .semibold : .medium))
        .foregroundStyle(period.isMinuteK ? .primary : .secondary)
        .frame(maxWidth: .infinity)
        .background {
            periodSelectionBackground(isSelected: period.isMinuteK)
        }
    }

    private func periodControlLabel(
        _ title: String,
        isSelected: Bool
    ) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: true, vertical: false)
            .font(.system(size: 9, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 20)
            .contentShape(Rectangle())
            .background {
                periodSelectionBackground(isSelected: isSelected)
            }
    }

    @ViewBuilder
    private func periodSelectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(.separator.opacity(0.6), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var chart: some View {
        ZStack {
            if chartCandles.isEmpty {
                if candlesKey == chartRequest {
                    // The load for what is on screen came back with nothing.
                    // Anything else — a switch still settling, a request in
                    // flight — is not yet an answer and must not claim to be one.
                    ContentUnavailableView {
                        Label(PulseLocalization.localizedString("chart.noData"), systemImage: "chart.xyaxis.line")
                    } description: {
                        Text(PulseLocalization.localizedString("chart.noPeriodData", period.displayName))
                    }
                    .transition(.opacity)
                } else if isLoading {
                    ChartLoadingView()
                        .transition(.opacity)
                }
                // Otherwise nothing yet: a load that answers inside the spinner's
                // 150ms grace period goes straight to the chart.
            } else if period == .minute1 {
                IntradayChartView(
                    candles: sourceCandles,
                    previousClose: quote?.previousClose ?? sourceCandles.first?.open ?? 0,
                    market: symbol.market,
                    palette: appState.palette,
                    showsExtendedHours: appState.showsExtendedHours(for: symbol)
                )
                .transition(.opacity)
            } else {
                CandlestickChartView(
                    candles: chartCandles,
                    palette: appState.palette,
                    period: period,
                    market: symbol.market,
                    highlightsExtendedHours: period.isMinuteK
                        && appState.showsExtendedHours(for: symbol),
                    transactions: period == .day
                        ? item?.materializedTransactions() ?? []
                        : [],
                    currencyCode: currencyCode,
                    viewport: candleViewport
                )
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: chartCandles.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Market stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderText(PulseLocalization.localizedString("detail.section.market"))
            HStack(spacing: 8) {
                stat(PulseLocalization.localizedString("stat.open"), quote?.open.map { PriceFormatter.price($0, market: symbol.market) })
                stat(PulseLocalization.localizedString("stat.high"), quote?.high.map { PriceFormatter.price($0, market: symbol.market) })
                stat(PulseLocalization.localizedString("stat.low"), quote?.low.map { PriceFormatter.price($0, market: symbol.market) })
            }
            HStack(spacing: 8) {
                stat(PulseLocalization.localizedString("stat.previousClose"), quote.map { PriceFormatter.price($0.previousClose, market: symbol.market) })
                stat(PulseLocalization.localizedString("stat.volume"), quote?.volume.map(PriceFormatter.compact))
                stat(PulseLocalization.localizedString("stat.amplitude"), quote?.amplitudePercent.map(PriceFormatter.percentMagnitude))
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Position

    @ViewBuilder
    private var positionArea: some View {
        if let item, item.supportsPosition {
            sectionSeparator
            positionSection
        } else if let item, item.hasPosition {
            sectionSeparator
            legacyIndexPositionSection
        } else {
            // Position sections supply this inset themselves. Keep the same
            // bottom breathing room when indices intentionally omit the section.
            Color.clear
                .frame(height: 12)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var positionSection: some View {
        Group {
            if let item, item.hasPosition {
                // The whole summary is the way into the position hub — same
                // destination as the header briefcase, but where the eye
                // already is.
                Button {
                    route = .position(item.symbol, .detail(symbol))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            sectionHeaderText(PulseLocalization.localizedString("detail.section.position"))
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        if let quote, let metrics = PositionMetrics(item: item, quote: quote) {
                            HStack(spacing: 8) {
                                pnlCell(PulseLocalization.localizedString("metric.todayPnL"), amount: metrics.todayPnL, percent: metrics.todayReturnPercent)
                                pnlCell(PulseLocalization.localizedString("metric.totalPnL"), amount: metrics.totalPnL, percent: metrics.totalReturnPercent)
                            }
                            HStack(spacing: 8) {
                                stat(PulseLocalization.localizedString("position.quantity"), PriceFormatter.quantity(metrics.quantity))
                                stat(PulseLocalization.localizedString("position.cost"), PriceFormatter.price(metrics.averageCost))
                                stat(PulseLocalization.localizedString("position.marketValue"), PriceFormatter.money(metrics.marketValue, currencyCode: currencyCode))
                            }
                        } else {
                            Text(PulseLocalization.localizedString("position.waitingQuote"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            } else if let item, item.hasPositionHistory {
                // Selling out is not the same as never having held: the trade
                // log and what it realized outlive the position, and dropping
                // straight back to "no position" reads as if the record was
                // lost. Same target and same whole-block tap as an open one.
                Button {
                    route = .position(item.symbol, .detail(symbol))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            sectionHeaderText(PulseLocalization.localizedString("detail.section.position"))
                            Text(PulseLocalization.localizedString("position.closed"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        HStack(spacing: 8) {
                            stat(
                                PulseLocalization.localizedString("position.realizedPnL"),
                                PriceFormatter.signedMoney(item.realizedPnL, currencyCode: currencyCode),
                                color: item.realizedPnL
                            )
                            stat(
                                PulseLocalization.localizedString("position.historyTrades"),
                                PulseLocalization.localizedString("position.tradeCount", item.transactions.count)
                            )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeaderText(PulseLocalization.localizedString("detail.section.position"))
                    HStack {
                        Text(PulseLocalization.localizedString("position.notSet"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if let item {
                            Button(PulseLocalization.localizedString("action.addPosition")) {
                                route = .position(item.symbol, .detail(symbol))
                            }
                            .buttonStyle(.pressable)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var legacyIndexPositionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderText(PulseLocalization.localizedString("detail.section.position"))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(PulseLocalization.localizedString("position.indexLegacyNotice"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(PulseLocalization.localizedString("action.clearPosition"), role: .destructive) {
                    appState.watchlist.clearPosition(symbol)
                }
                .buttonStyle(.pressable)
                .font(.system(size: 10.5, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    /// P&L cell: signed amount with its percent on a shared baseline, tinted by direction.
    private func pnlCell(_ label: String, amount: Double, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(PriceFormatter.signedMoney(amount, currencyCode: currencyCode))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                Text(PriceFormatter.percent(percent))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .opacity(0.9)
            }
            .foregroundStyle(appState.palette.color(for: amount))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared pieces

    private var sectionSeparator: some View {
        Divider()
            .opacity(0.45)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func sectionHeaderText(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// `color` carries a signed amount when the value should read as a gain or
    /// a loss; without it the stat stays neutral, like quantity or cost.
    private func stat(_ label: String, _ value: String?, color: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
            Text(value ?? "—")
                .font(.system(size: 10.5, weight: color == nil ? .medium : .semibold).monospacedDigit())
                .foregroundStyle(color.map { appState.palette.color(for: $0) } ?? .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
