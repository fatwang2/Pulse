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
            quoteSummary
            statsGrid
            positionSection
            picker
            chart
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
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
                IconButton(systemName: "pencil", help: "编辑持仓") {
                    route = .position(item.symbol, .detail(symbol))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var quoteSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let quote {
                let color = appState.palette.color(for: quote.change)
                Text(PriceFormatter.price(quote.price))
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(PriceFormatter.change(quote.change))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(color)
                Text(PriceFormatter.percent(quote.changePercent))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let currency = quote.currencyCode {
                        Text(currency)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    let delay = appState.quoteDelay(for: symbol.market)
                    if delay > 0 {
                        Text("延时约\(Int(delay / 60))分钟")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("—").font(.title2)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var positionSection: some View {
        if let item {
            if let quote, let metrics = PositionMetrics(item: item, quote: quote) {
                VStack(spacing: 7) {
                    HStack {
                        Text("持仓")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("编辑") {
                            route = .position(item.symbol, .detail(symbol))
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                    }
                    HStack(spacing: 0) {
                        positionStat("数量", PriceFormatter.quantity(metrics.quantity))
                        positionStat("成本", PriceFormatter.price(metrics.averageCost))
                        positionStat("市值", PriceFormatter.money(metrics.marketValue, currencyCode: currencyCode))
                    }
                    HStack(spacing: 0) {
                        pnlStat("今日", value: metrics.todayPnL, percent: metrics.todayReturnPercent)
                        pnlStat("持仓", value: metrics.totalPnL, percent: metrics.totalReturnPercent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            } else {
                Button {
                    route = .position(item.symbol, .detail(symbol))
                } label: {
                    HStack {
                        Label("录入持仓数量和成本价", systemImage: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            }
        }
    }

    private var currencyCode: String? {
        quote?.currencyCode ?? symbol.market.currencyCode
    }

    private func positionStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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

    private func pnlStat(_ label: String, value: Double, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text("\(PriceFormatter.signedMoney(value, currencyCode: currencyCode)) · \(PriceFormatter.percent(percent))")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(appState.palette.color(for: value))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var picker: some View {
        Picker("周期", selection: $period) {
            ForEach(Self.periods, id: \.self) { p in
                Text(p.displayName).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
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
                    palette: appState.palette
                )
            } else {
                CandlestickChartView(candles: candles, palette: appState.palette, period: period)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
