import SwiftUI
import PulseCore
import PulseUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let symbol: SymbolID
    @Binding var route: PopoverRoute

    @State private var period: CandlePeriod = .minute1
    @State private var candles: [Candle] = []
    @State private var isLoading = false
    @State private var isFirstLoad = true
    @State private var shareFeedback: ShareFeedback?

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
        .safeAreaInset(edge: .top, spacing: 0) { header }
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
        .task(id: period) {
            let taskStart = ContinuousClock.now
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
                for: symbol, period: period,
                count: candleCount(for: period)
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
            }
        }
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
            }
            let historyDays = symbol.market == .crypto ? 1 : 5
            return min(max(sessionMinutes / minutes * historyDays, 240), 1_000)
        case .day: return 250
        case .week: return 260
        case .month: return 240
        case .minute1:
            return IntradayTrendSnapshot.recommendedCandleCount(for: symbol.market)
        }
    }

    /// Minute K data is fetched with all US sessions so the setting can switch instantly.
    /// This also removes overnight bars: Pulse's setting promises pre/post, not 24-hour US trading.
    private var chartCandles: [Candle] {
        guard period.isMinuteK else { return candles }
        return IntradayTradingSession.filterCandles(
            candles,
            market: symbol.market,
            includesExtendedHours: appState.settings.showsUSExtendedHours
        )
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.back")) {
                route = .list
            }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            ClusterIcon(
                systemName: "square.and.arrow.up",
                help: PulseLocalization.localizedString("action.copyShareSnapshot")
            ) {
                copyShareSnapshot()
            }
            .disabled(quote == nil || chartCandles.isEmpty)
            .opacity(quote == nil || chartCandles.isEmpty ? 0.45 : 1)
            if item == nil {
                // Opened from search without being watched: offer the add here so
                // a lookup can graduate into the list without going back.
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
            if let item, item.supportsPosition {
                ClusterIcon(
                    systemName: item.hasPosition ? "briefcase.fill" : "briefcase",
                    help: item.hasPosition
                        ? PulseLocalization.localizedString("action.editPosition")
                        : PulseLocalization.localizedString("action.addPosition")
                ) {
                    route = .position(item.symbol, .detail(symbol))
                }
            }
        }
        .overlay(alignment: .trailing) {
            if let shareFeedback {
                ShareFeedbackHUD(feedback: shareFeedback)
                    .padding(.trailing, item?.supportsPosition == true ? 58 : 30)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
    private func copyShareSnapshot() {
        do {
            let snapshot = DetailShareSnapshot(
                appState: appState,
                symbol: symbol,
                period: period,
                candles: chartCandles
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
            showShareFeedback(isSuccess: true)
        } catch {
            showShareFeedback(isSuccess: false)
        }
    }

    @MainActor
    private func showShareFeedback(isSuccess: Bool) {
        let feedback = ShareFeedback(isSuccess: isSuccess)
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
                        Text(PriceFormatter.price(quote.price))
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .foregroundStyle(color)
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: quote.price))
                            .animation(.snappy(duration: 0.25), value: quote.price)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if let currency = quote.currencyCode {
                            Text(currency)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(PriceFormatter.change(quote.change))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                        Text(PriceFormatter.percent(quote.changePercent))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(color)
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
            if let quote {
                quoteMeta(for: quote)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    /// Quote provenance at the hero's top-right: freshness, source, then market-time basis.
    /// Bottom-aligns with the price block so the metadata reads as an annotation to the quote.
    private func quoteMeta(for quote: Quote) -> some View {
        let delayText = appState.quoteDelayText(for: quote)
        return VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(delayText == nil ? Color.green.opacity(0.8) : .orange)
                    .frame(width: 5, height: 5)
                Text(delayText ?? PulseLocalization.localizedString("quote.realtime"))
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
                if isLoading {
                    ProgressView().controlSize(.small)
                        .transition(.opacity)
                } else {
                    ContentUnavailableView {
                        Label(PulseLocalization.localizedString("chart.noData"), systemImage: "chart.xyaxis.line")
                    } description: {
                        Text(PulseLocalization.localizedString("chart.noPeriodData", period.displayName))
                    }
                    .transition(.opacity)
                }
            } else if period == .minute1 {
                IntradayChartView(
                    candles: candles,
                    previousClose: quote?.previousClose ?? candles.first?.open ?? 0,
                    market: symbol.market,
                    palette: appState.palette,
                    showsExtendedHours: appState.settings.showsUSExtendedHours
                )
                .transition(.opacity)
            } else {
                CandlestickChartView(
                    candles: chartCandles,
                    palette: appState.palette,
                    period: period,
                    market: symbol.market,
                    highlightsExtendedHours: symbol.market == .us
                        && period.isMinuteK
                        && appState.settings.showsUSExtendedHours
                )
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: candles.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Market stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderText(PulseLocalization.localizedString("detail.section.market"))
            HStack(spacing: 8) {
                stat(PulseLocalization.localizedString("stat.open"), quote?.open.map(PriceFormatter.price))
                stat(PulseLocalization.localizedString("stat.high"), quote?.high.map(PriceFormatter.price))
                stat(PulseLocalization.localizedString("stat.low"), quote?.low.map(PriceFormatter.price))
            }
            HStack(spacing: 8) {
                stat(PulseLocalization.localizedString("stat.previousClose"), quote.map { PriceFormatter.price($0.previousClose) })
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
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderText(PulseLocalization.localizedString("detail.section.position"))
            if let item, item.hasPosition {
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
            } else {
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

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
            Text(value ?? "—")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
