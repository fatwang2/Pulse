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
            header
            Divider()
            quoteSummary
            statsGrid
            picker
            chart
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .glassEffect(.regular.tint(color), in: RoundedRectangle(cornerRadius: 6))
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

    private func stat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value ?? "—")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
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
