import SwiftUI
import Charts
import PulseCore

/// Candlestick chart (daily/weekly/monthly) with a volume strip at the bottom.
/// The X axis uses indices rather than dates to avoid gaps from weekends/trading halts; axis labels map back to dates.
/// Mark building is extracted into @ChartContentBuilder functions: clearer structure, and it avoids type-check timeouts in deeply nested branches on SDK 27.
public struct CandlestickChartView: View {
    let candles: [Candle]
    let palette: ChangePalette
    let period: CandlePeriod

    public init(candles: [Candle], palette: ChangePalette, period: CandlePeriod = .day) {
        self.candles = candles
        self.palette = palette
        self.period = period
    }

    public var body: some View {
        VStack(spacing: 2) {
            Chart {
                candleMarks
            }
            .chartYScale(domain: priceDomain)
            .chartXScale(domain: xDomain)
            .chartXAxis {
                AxisMarks(values: axisIndices) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    if let index = value.as(Int.self), let candle = candles[safe: index] {
                        AxisValueLabel(dateLabel(for: candle)).font(.caption2)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    if let v = value.as(Double.self) {
                        AxisValueLabel(PriceFormatter.price(v)).font(.caption2)
                    }
                }
            }

            Chart {
                volumeMarks
            }
            .chartXScale(domain: xDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
        }
    }

    // MARK: - Marks

    @ChartContentBuilder
    private var candleMarks: some ChartContent {
        ForEach(Array(candles.enumerated()), id: \.offset) { index, candle in
            RuleMark(x: .value("i", index),
                     yStart: .value("Low", candle.low),
                     yEnd: .value("High", candle.high))
                .foregroundStyle(palette.color(isUp: candle.isUp))
                .lineStyle(StrokeStyle(lineWidth: 1))
            RectangleMark(x: .value("i", index),
                          yStart: .value("Open", bodyLow(candle)),
                          yEnd: .value("Close", bodyHigh(candle)),
                          width: .ratio(0.62))
                .foregroundStyle(palette.color(isUp: candle.isUp))
        }
    }

    @ChartContentBuilder
    private var volumeMarks: some ChartContent {
        ForEach(Array(candles.enumerated()), id: \.offset) { index, candle in
            BarMark(x: .value("i", index),
                    y: .value("Volume", candle.volume ?? 0),
                    width: .ratio(0.62))
                .foregroundStyle(palette.color(isUp: candle.isUp).opacity(0.55))
        }
    }

    // MARK: - Layout math

    /// Doji candles (open == close) still need a visible body: give them a tiny minimum height
    private func bodyLow(_ candle: Candle) -> Double {
        min(candle.open, candle.close)
    }

    private func bodyHigh(_ candle: Candle) -> Double {
        let high = max(candle.open, candle.close)
        let minBody = (priceDomain.upperBound - priceDomain.lowerBound) * 0.002
        return high - bodyLow(candle) < minBody ? bodyLow(candle) + minBody : high
    }

    private var priceDomain: ClosedRange<Double> {
        let lo = candles.map(\.low).min() ?? 0
        let hi = candles.map(\.high).max() ?? 1
        let pad = max((hi - lo) * 0.05, hi * 0.001)
        return (lo - pad)...(hi + pad)
    }

    private var xDomain: ClosedRange<Int> {
        -1...max(candles.count, 1)
    }

    private var axisIndices: [Int] {
        guard candles.count > 1 else { return [0] }
        let count = 4
        let step = max(candles.count / count, 1)
        return Array(stride(from: 0, to: candles.count, by: step))
    }

    private func dateLabel(for candle: Candle) -> String {
        switch period {
        case .month, .week:
            candle.time.formatted(.dateTime.year(.twoDigits).month(.twoDigits))
        default:
            candle.time.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
