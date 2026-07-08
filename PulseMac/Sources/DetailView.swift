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

    var body: some View {
        VStack(spacing: 0) {
            marketSection
            sectionSeparator
            positionSection
            sectionSeparator
            chartSection
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

    private var marketSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            quoteSummary
            statsGrid
        }
        .padding(.top, 4)
    }

    private var chartSection: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center) {
                sectionHeaderText("趋势")
                Spacer()
                picker
            }
            .padding(.horizontal, 12)
            chart
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    private var quoteSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            if let quote {
                let color = appState.palette.color(for: quote.change)
                VStack(alignment: .leading, spacing: 3) {
                    Text(quotePriceLabel(for: quote))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(PriceFormatter.price(quote.price))
                            .font(.system(size: 26, weight: .semibold).monospacedDigit())
                            .foregroundStyle(color)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if let currency = quote.currencyCode {
                            Text(currency)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(PriceFormatter.change(quote.change))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(color)
                        Text(PriceFormatter.percent(quote.changePercent))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(color)
                    }
                }
                .layoutPriority(1)
                Spacer()
                quoteMeta(for: quote)
            } else {
                Text("—").font(.title2)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
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

    private func quoteMeta(for quote: Quote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let sourceName = quote.sourceName {
                quoteMetaRow("来源", sourceName)
            }
            quoteMetaRow("时间", appState.quoteMarketTimeText(for: quote))
            quoteMetaRow("状态", appState.quoteDelayText(for: quote) ?? "实时", isWarning: appState.quoteDelayText(for: quote) != nil)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .allowsTightening(true)
        .frame(width: 128, alignment: .leading)
    }

    private func quoteMetaRow(_ label: String, _ value: String, isWarning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .frame(width: 24, alignment: .leading)
                .foregroundStyle(.quaternary)
            if isWarning {
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(Color.orange.opacity(0.85))
            } else {
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            stat("今开", quote?.open.map(PriceFormatter.price))
            stat("最高", quote?.high.map(PriceFormatter.price))
            stat("最低", quote?.low.map(PriceFormatter.price))
            stat("成交量", quote?.volume.map(PriceFormatter.compact))
            stat("成交额", quote?.turnover.map(PriceFormatter.compact))
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var positionSection: some View {
        VStack(spacing: 7) {
            HStack {
                sectionHeaderText("持仓")
                Spacer()
            }
            if let item, item.hasPosition,
               let quote, let metrics = PositionMetrics(item: item, quote: quote) {
                HStack(spacing: 0) {
                    positionStat("数量", PriceFormatter.quantity(metrics.quantity))
                    positionStat("成本", PriceFormatter.price(metrics.averageCost))
                    positionStat("市值", PriceFormatter.money(metrics.marketValue, currencyCode: currencyCode))
                }
                HStack(spacing: 10) {
                    pnlStat(
                        "今日金额",
                        PriceFormatter.signedMoney(metrics.todayPnL, currencyCode: currencyCode),
                        colorBasis: metrics.todayPnL
                    )
                    pnlStat(
                        "今日涨幅",
                        PriceFormatter.percent(metrics.todayReturnPercent),
                        colorBasis: metrics.todayReturnPercent
                    )
                    pnlStat(
                        "持仓金额",
                        PriceFormatter.signedMoney(metrics.totalPnL, currencyCode: currencyCode),
                        colorBasis: metrics.totalPnL
                    )
                    pnlStat(
                        "持仓涨幅",
                        PriceFormatter.percent(metrics.totalReturnPercent),
                        colorBasis: metrics.totalReturnPercent
                    )
                }
            } else {
                Text("未录入持仓")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 12)
    }

    private var currencyCode: String? {
        quote?.currencyCode ?? symbol.market.currencyCode
    }

    private func positionStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pnlStat(_ label: String, _ value: String, colorBasis: Double) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(appState.palette.color(for: colorBasis))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
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
}
