import SwiftUI
import Charts
import PulseCore

/// Intraday chart: today's trend plus a dashed previous-close baseline; the overall tint follows the price change.
public struct IntradayChartView: View {
    let candles: [Candle]
    let previousClose: Double
    let palette: ChangePalette

    public init(candles: [Candle], previousClose: Double, palette: ChangePalette) {
        self.candles = candles
        self.previousClose = previousClose
        self.palette = palette
    }

    private var tint: Color {
        guard let last = candles.last else { return .secondary }
        return palette.color(for: last.close - previousClose)
    }

    public var body: some View {
        Chart {
            marks
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(format: .dateTime.hour().minute(), centered: false)
                    .font(.caption2)
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
    }

    @ChartContentBuilder
    private var marks: some ChartContent {
        ForEach(candles, id: \.time) { candle in
            LineMark(x: .value("Time", candle.time), y: .value("Price", candle.close))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            AreaMark(x: .value("Time", candle.time),
                     yStart: .value("Baseline", yDomain.lowerBound),
                     yEnd: .value("Price", candle.close))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
        }
        RuleMark(y: .value("Prev Close", previousClose))
            .foregroundStyle(.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            .annotation(position: .topLeading, spacing: 2) {
                Text("昨收 \(PriceFormatter.price(previousClose))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
    }

    private var yDomain: ClosedRange<Double> {
        let closes = candles.map(\.close)
        var lo = min(closes.min() ?? previousClose, previousClose)
        var hi = max(closes.max() ?? previousClose, previousClose)
        let pad = max((hi - lo) * 0.1, hi * 0.001)
        lo -= pad
        hi += pad
        return lo...hi
    }
}
