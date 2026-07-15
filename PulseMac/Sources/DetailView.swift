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

    private static let periods: [CandlePeriod] = [.minute1, .day, .week, .month]

    // Page flow: price hero → trend chart → market stats → position.
    // Source/time/delay metadata sits at the hero's top-right corner, annotating the price.
    var body: some View {
        VStack(spacing: 0) {
            heroSection
            sectionSeparator
            chartSection
            sectionSeparator
            statsSection
            sectionSeparator
            positionSection
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
        quote?.currencyCode ?? symbol.market.currencyCode
    }

    private func candleCount(for period: CandlePeriod) -> Int {
        guard period.isIntraday else { return 90 }
        if symbol.market == .crypto {
            return period == .minute1 ? 24 * 60 : 24 * 12
        }
        return 400
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.back")) {
                route = .list
            }
            HStack(spacing: 6) {
                Text(quote?.name ?? symbol.code)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                MarketBadge(market: symbol.market)
                    .fixedSize()
                Text(symbol.code)
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
            .disabled(quote == nil || candles.isEmpty)
            .opacity(quote == nil || candles.isEmpty ? 0.45 : 1)
            if let item {
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
                    .padding(.trailing, item == nil ? 30 : 58)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    @MainActor
    private func copyShareSnapshot() {
        do {
            let snapshot = DetailShareSnapshot(
                appState: appState,
                symbol: symbol,
                period: period,
                candles: candles
            )
            let card = PulseShareCard(
                metadata: PulseShareCardMetadata(updatedAtText: snapshot.updatedAtText)
            ) {
                DetailShareContent(snapshot: snapshot)
            }
            let artifact = try ShareImageRenderer.render(
                card,
                configuration: .socialPortrait(
                    height: snapshot.preferredImageHeight,
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
        Picker(PulseLocalization.localizedString("detail.period"), selection: $period) {
            ForEach(Self.periods, id: \.self) { p in
                Text(p.displayName).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var chart: some View {
        ZStack {
            if candles.isEmpty {
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
            } else if period.isIntraday {
                IntradayChartView(
                    candles: candles,
                    previousClose: quote?.previousClose ?? candles.first?.open ?? 0,
                    market: symbol.market,
                    palette: appState.palette
                )
                .transition(.opacity)
            } else {
                CandlestickChartView(candles: candles, palette: appState.palette, period: period)
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
