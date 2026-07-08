import SwiftUI
import Charts
import PulseCore

/// Intraday chart: today's trend plus a dashed previous-close baseline; the overall tint follows the price change.
public struct IntradayChartView: View {
    let candles: [Candle]
    let previousClose: Double
    let market: Market
    let palette: ChangePalette

    public init(candles: [Candle], previousClose: Double, market: Market, palette: ChangePalette) {
        self.candles = candles
        self.previousClose = previousClose
        self.market = market
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
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xAxisValues) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel(centered: false) {
                    if let date = value.as(Date.self) {
                        Text(axisTimeFormatter.string(from: date))
                            .font(.caption2)
                    }
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
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.leading, 2)
                .padding(.trailing, 6)
        }
    }

    @ChartContentBuilder
    private var marks: some ChartContent {
        ForEach(lineSegments) { segment in
            ForEach(segment.candles, id: \.time) { candle in
                LineMark(
                    x: .value("Time", candle.time),
                    y: .value("Price", candle.close),
                    series: .value("Session", segment.id)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                AreaMark(
                    x: .value("Time", candle.time),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Price", candle.close),
                    series: .value("Session", segment.id)
                )
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            }
        }
        RuleMark(y: .value("Prev Close", previousClose))
            .foregroundStyle(.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
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

    private var xDomain: ClosedRange<Date> {
        let sorted = candles.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else {
            let now = Date()
            return now...now
        }
        let window = tradingWindow(containing: first.time)
        return min(first.time, window.lowerBound)...max(last.time, window.upperBound)
    }

    private var xAxisValues: [Date] {
        guard let first = candles.min(by: { $0.time < $1.time }) else { return [] }
        let calendar = marketCalendar
        let day = calendar.startOfDay(for: first.time)
        let hours: [Int] = switch market {
        case .sh, .sz:
            [10, 11, 13, 14]
        case .hk:
            [10, 11, 13, 14, 15]
        case .us:
            [10, 11, 12, 13, 14, 15]
        }
        return hours.compactMap { hour in
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }
    }

    private var lineSegments: [CandleSegment] {
        let sorted = candles.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return [] }
        var segments: [CandleSegment] = []
        var current = [first]
        for candle in sorted.dropFirst() {
            if let previous = current.last,
               candle.time.timeIntervalSince(previous.time) > segmentBreakInterval {
                segments.append(CandleSegment(id: segments.count, candles: current))
                current = [candle]
            } else {
                current.append(candle)
            }
        }
        segments.append(CandleSegment(id: segments.count, candles: current))
        return segments
    }

    private var segmentBreakInterval: TimeInterval {
        market.isChinaA || market == .hk ? 30 * 60 : 20 * 60
    }

    private var marketCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = market.timeZone
        return calendar
    }

    private var axisTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        formatter.timeZone = market.timeZone
        return formatter
    }

    private func tradingWindow(containing date: Date) -> ClosedRange<Date> {
        let calendar = marketCalendar
        let day = calendar.startOfDay(for: date)
        let open = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day) ?? date
        let closeHour = market.isChinaA ? 15 : 16
        let close = calendar.date(bySettingHour: closeHour, minute: 0, second: 0, of: day) ?? date
        return open...close
    }
}

private struct CandleSegment: Identifiable {
    let id: Int
    let candles: [Candle]
}
