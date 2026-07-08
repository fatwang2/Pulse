import SwiftUI
import PulseCore
import PulseUI

struct DetailView: View {
    @Environment(AppState.self) private var appState
    let symbol: SymbolID
    @Binding var route: PopoverRoute

    @State private var period: CandlePeriod = .minute1
    @State private var candles: [Candle] = []
    @State private var isLoading = false

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
        .task(id: period) {
            isLoading = true
            defer { isLoading = false }
            candles = await appState.engine.loadCandles(
                for: symbol, period: period,
                count: period.isIntraday ? 400 : 90
            )
        }
    }

    private var quote: Quote? { appState.market.quote(for: symbol) }
    private var item: WatchItem? { appState.watchlist.item(for: symbol) }

    private var currencyCode: String? {
        quote?.currencyCode ?? symbol.market.currencyCode
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: "返回") {
                route = .list
            }
            HStack(spacing: 6) {
                Text(quote?.name ?? symbol.code)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                MarketBadge(market: symbol.market)
                Text(symbol.code)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let item {
                ClusterIcon(
                    systemName: item.hasPosition ? "briefcase.fill" : "briefcase",
                    help: item.hasPosition ? "编辑持仓" : "录入持仓"
                ) {
                    route = .position(item.symbol, .detail(symbol))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .top, spacing: 12) {
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
                            .contentTransition(.numericText())
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
                    Text("现价")
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

    /// Quote provenance at the hero's top-right: source · market time, then freshness.
    /// The first line top-aligns with the price label on the left.
    private func quoteMeta(for quote: Quote) -> some View {
        let delayText = appState.quoteDelayText(for: quote)
        return VStack(alignment: .trailing, spacing: 4) {
            Text([quote.sourceName, appState.quoteMarketTimeText(for: quote)]
                .compactMap { $0 }
                .joined(separator: " · "))
                .foregroundStyle(.tertiary)
            HStack(spacing: 4) {
                Circle()
                    .fill(delayText == nil ? Color.green.opacity(0.8) : .orange)
                    .frame(width: 5, height: 5)
                Text(delayText ?? "实时")
                    .foregroundStyle(delayText == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.orange.opacity(0.85)))
            }
        }
        .font(.system(size: 9, weight: .medium))
        .lineLimit(1)
        .fixedSize()
    }

    private func quotePriceLabel(for quote: Quote) -> String {
        switch quote.marketState {
        case .preMarket:
            "盘前价"
        case .postMarket:
            "盘后价"
        case .closed:
            "收盘价"
        case .regular, .none:
            "现价"
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center) {
                sectionHeaderText("趋势")
                Spacer()
                picker
            }
            .padding(.horizontal, 12)
            // Leading 10 + the intraday plot's own 2pt inset lands the plot edge on the 12pt text grid;
            // trailing 12 aligns the y-axis labels with it directly.
            chart
                .padding(.leading, 10)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var picker: some View {
        Picker("周期", selection: $period) {
            ForEach(Self.periods, id: \.self) { p in
                Text(p.displayName).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .frame(width: 148)
    }

    @ViewBuilder
    private var chart: some View {
        ZStack {
            if candles.isEmpty {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    ContentUnavailableView {
                        Label("暂无数据", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("当前数据源没有该标的的\(period.displayName)数据")
                    }
                }
            } else if period.isIntraday {
                IntradayChartView(
                    candles: candles,
                    previousClose: quote?.previousClose ?? candles.first?.open ?? 0,
                    market: symbol.market,
                    palette: appState.palette
                )
            } else {
                CandlestickChartView(candles: candles, palette: appState.palette, period: period)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Market stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderText("行情")
            HStack(spacing: 8) {
                stat("今开", quote?.open.map(PriceFormatter.price))
                stat("最高", quote?.high.map(PriceFormatter.price))
                stat("最低", quote?.low.map(PriceFormatter.price))
            }
            HStack(spacing: 8) {
                stat("昨收", quote.map { PriceFormatter.price($0.previousClose) })
                stat("成交量", quote?.volume.map(PriceFormatter.compact))
                stat("成交额", quote?.turnover.map(PriceFormatter.compact))
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Position

    @ViewBuilder
    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeaderText("持仓")
            if let item, item.hasPosition {
                if let quote, let metrics = PositionMetrics(item: item, quote: quote) {
                    HStack(spacing: 8) {
                        pnlCell("今日盈亏", amount: metrics.todayPnL, percent: metrics.todayReturnPercent)
                        pnlCell("持仓盈亏", amount: metrics.totalPnL, percent: metrics.totalReturnPercent)
                    }
                    HStack(spacing: 8) {
                        stat("数量", PriceFormatter.quantity(metrics.quantity))
                        stat("成本", PriceFormatter.price(metrics.averageCost))
                        stat("市值", PriceFormatter.money(metrics.marketValue, currencyCode: currencyCode))
                    }
                } else {
                    Text("等待行情数据…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            } else {
                HStack {
                    Text("未录入持仓")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if let item {
                        Button("录入持仓") {
                            route = .position(item.symbol, .detail(symbol))
                        }
                        .buttonStyle(.plain)
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
    }

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
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
