import SwiftUI
import PulseCore
import PulseUI

/// Instrument page: price hero → period chips → trend chart → market stats.
/// The loading discipline mirrors the Mac DetailView: cache paints first, the
/// fresh answer replaces it in place, and stale bars never masquerade as the
/// period on screen.
struct DetailScreen: View {
    @Environment(IOSAppState.self) private var appState

    let symbol: SymbolID

    @State private var period: CandlePeriod = .minute1
    @State private var candles: [Candle] = []
    /// What `candles` hold, and by the same token which request they answer for.
    @State private var candlesKey: CandleCacheKey?
    @State private var isLoading = false
    @State private var isFirstLoad = true

    private static let periods: [CandlePeriod] = [
        .minute1, .minute5, .minute15, .minute30, .hour1, .day, .week, .month,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroSection
                periodChips
                chartSection
                statsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .navigationTitle(appState.displayName(for: symbol))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                watchButton
            }
        }
        .onAppear { period = initialPeriod }
        // Real-time push while the page is on screen; polling remains the fallback.
        .task(id: symbol) {
            guard let stream = appState.provider.quoteStream(for: [symbol]) else { return }
            do {
                for try await quote in stream {
                    appState.ingestStreamedQuote(quote)
                }
            } catch {
                // Stream dropped — the polling loop still updates the page.
            }
        }
        // Symbols opened from search aren't in the watchlist, so the engine's
        // polling loop never covers them; run a light poll until the page closes.
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
            await loadChart()
        }
    }

    // MARK: - Chart loading

    private var chartRequest: CandleCacheKey {
        CandleCacheKey(symbol: symbol, period: period)
    }

    private func loadChart() async {
        let request = chartRequest
        // Switching periods repaints from whatever is already cached for the
        // new one, however old; the refresh replaces it in place.
        if !isFirstLoad,
           let cached = appState.market.cachedCandles(for: request, maxAge: .infinity),
           !cached.isEmpty {
            candles = cached
            candlesKey = request
        }
        // Show the spinner only when loading is actually slow: a fast cache hit
        // swaps silently instead of flashing a progress indicator.
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
        isFirstLoad = false
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            candles = loaded
            candlesKey = request
        }
    }

    /// K-line periods load history behind the zoomable window. Intraday
    /// resolutions retain enough bars to look back while staying inside
    /// Binance's 1,000-candle request ceiling.
    private func candleCount(for period: CandlePeriod) -> Int {
        switch period {
        case .minute5, .minute15, .minute30, .hour1:
            guard let minutes = period.intradayMinutes else { return 240 }
            let sessionMinutes = switch symbol.market {
            case .sh, .sz: 240
            case .hk: 330
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

    /// Only bars that belong to what is on screen now.
    private var sourceCandles: [Candle] {
        if candlesKey == chartRequest { return candles }
        guard !isFirstLoad else { return [] }
        return appState.market.cachedCandles(for: chartRequest, maxAge: .infinity) ?? []
    }

    /// Minute K data is fetched with all US sessions so the setting can switch
    /// instantly; this also removes overnight bars.
    private var chartCandles: [Candle] {
        guard period.isMinuteK else { return sourceCandles }
        return IntradayTradingSession.filterCandles(
            sourceCandles,
            market: symbol.market,
            includesExtendedHours: appState.showsExtendedHours(for: symbol)
        )
    }

    private var initialPeriod: CandlePeriod {
        appState.settings.lastCandlePeriod
    }

    // MARK: - Hero

    private var quote: Quote? { appState.market.quote(for: symbol) }
    private var item: WatchItem? { appState.watchlist.item(for: symbol) }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MarketBadge(market: symbol.market)
                Text(symbol.displayCode)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if symbol.isDescribable {
                    Spacer(minLength: 8)
                    NavigationLink(value: IOSRoute.profile(symbol)) {
                        HStack(spacing: 2) {
                            Text(PulseLocalization.localizedString("detail.section.about"))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let quote {
                Text(priceLabel(for: quote))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(PriceFormatter.price(quote.price))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(PriceFormatter.change(quote.change))
                        Text(PriceFormatter.percent(quote.changePercent))
                    }
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(appState.palette.color(for: quote.change))
                    .contentTransition(.numericText())
                }
                Text(appState.quoteTimingText(for: quote))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.default, value: quote?.price)
    }

    private func priceLabel(for quote: Quote) -> String {
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

    // MARK: - Period picker

    private var periodChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Self.periods, id: \.self) { candidate in
                    periodChip(candidate)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func periodChip(_ candidate: CandlePeriod) -> some View {
        let isSelected = period == candidate
        Button {
            period = candidate
            appState.settings.lastCandlePeriod = candidate
        } label: {
            Text(candidate.displayName)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(.capsule)
                .glassEffect(
                    isSelected ? .regular.tint(.accentColor).interactive() : .identity,
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Chart

    private var chartSection: some View {
        ZStack {
            if chartCandles.isEmpty {
                if candlesKey == chartRequest {
                    ContentUnavailableView {
                        Label(
                            PulseLocalization.localizedString("chart.noData"),
                            systemImage: "chart.xyaxis.line"
                        )
                    } description: {
                        Text(PulseLocalization.localizedString("chart.noPeriodData", period.displayName))
                    }
                } else if isLoading {
                    ChartLoadingView()
                }
            } else if period == .minute1 {
                IntradayChartView(
                    candles: sourceCandles,
                    previousClose: quote?.previousClose ?? sourceCandles.first?.open ?? 0,
                    market: symbol.market,
                    palette: appState.palette,
                    showsExtendedHours: appState.showsExtendedHours(for: symbol)
                )
            } else {
                CandlestickChartView(
                    candles: chartCandles,
                    palette: appState.palette,
                    period: period,
                    market: symbol.market,
                    highlightsExtendedHours: period.isMinuteK
                        && appState.showsExtendedHours(for: symbol),
                    currencyCode: quote?.currencyCode ?? symbol.currencyCode
                )
            }
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.18), value: chartCandles.isEmpty)
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PulseLocalization.localizedString("detail.section.market"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                stat(PulseLocalization.localizedString("stat.open"), quote?.open.map(PriceFormatter.price))
                stat(PulseLocalization.localizedString("stat.high"), quote?.high.map(PriceFormatter.price))
                stat(PulseLocalization.localizedString("stat.low"), quote?.low.map(PriceFormatter.price))
            }
            HStack(spacing: 8) {
                stat(
                    PulseLocalization.localizedString("stat.previousClose"),
                    quote.map { PriceFormatter.price($0.previousClose) }
                )
                stat(
                    PulseLocalization.localizedString("stat.volume"),
                    quote?.volume.map(PriceFormatter.compact)
                )
                stat(
                    PulseLocalization.localizedString("stat.turnover"),
                    quote?.turnover.map(PriceFormatter.compact)
                )
            }
        }
    }

    private func stat(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.callout.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Watch toggle

    private var isWatched: Bool { item != nil }

    private var watchButton: some View {
        Button {
            if isWatched {
                appState.watchlist.remove(symbol)
            } else {
                appState.watchlist.add(SymbolInfo(
                    symbol: symbol,
                    name: appState.displayName(for: symbol),
                    type: symbol.cryptoPair != nil ? .crypto : .equity
                ))
            }
            appState.watchlistSymbolsChanged()
        } label: {
            Label(
                PulseLocalization.localizedString(isWatched ? "action.removeFromWatchlist" : "action.addToWatchlist"),
                systemImage: isWatched ? "star.fill" : "star"
            )
        }
        .tint(isWatched ? .yellow : nil)
    }
}
