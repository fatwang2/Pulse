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

    @State private var hoveredIndex: Int?

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
            .chartOverlay { proxy in
                GeometryReader { geo in
                    priceCrosshair(proxy: proxy, geo: geo)
                }
            }

            Chart {
                volumeMarks
            }
            .chartXScale(domain: xDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 36)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    volumeCrosshair(proxy: proxy, geo: geo)
                }
            }
        }
        .onChange(of: candles) { _, _ in hoveredIndex = nil }
    }

    // MARK: - Crosshair

    @ViewBuilder
    private func priceCrosshair(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        ZStack(alignment: .topLeading) {
            hoverCatcher(plot: plot)
            if let index = hoveredIndex, let candle = candles[safe: index],
               let xPos = proxy.position(forX: index),
               let yPos = proxy.position(forY: candle.close) {
                let px = plot.origin.x + xPos
                let py = plot.origin.y + min(max(yPos, 0), plot.height)
                ChartCrosshair.lines(px: px, py: py, in: plot)
                priceTag(for: candle, py: py, geo: geo)
                readout(for: candle, previous: candles[safe: index - 1])
                    .padding(4)
                    .frame(width: plot.width, height: plot.height,
                           alignment: px > plot.midX ? .topLeading : .topTrailing)
                    .offset(x: plot.origin.x, y: plot.origin.y)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func volumeCrosshair(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        ZStack(alignment: .topLeading) {
            hoverCatcher(plot: plot)
            if let index = hoveredIndex, let xPos = proxy.position(forX: index) {
                ChartCrosshair.lines(px: plot.origin.x + xPos, py: nil, in: plot)
            }
        }
    }

    /// Transparent layer that tracks the cursor; both panes update the shared index,
    /// so the vertical line stays continuous across price and volume.
    private func hoverCatcher(plot: CGRect) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoveredIndex = index(at: point, plot: plot)
                case .ended:
                    hoveredIndex = nil
                }
            }
    }

    /// Invert the linear index scale by hand: `proxy.value(atX:)` on an Int scale truncates,
    /// which would make the snap lag half a candle behind the cursor.
    private func index(at point: CGPoint, plot: CGRect) -> Int? {
        guard !candles.isEmpty, plot.width > 0,
              plot.insetBy(dx: -2, dy: -4).contains(point) else { return nil }
        let rel = (point.x - plot.origin.x) / plot.width
        let raw = Double(xDomain.lowerBound) + rel * Double(xDomain.upperBound - xDomain.lowerBound)
        return min(max(Int(raw.rounded()), 0), candles.count - 1)
    }

    private func priceTag(for candle: Candle, py: CGFloat, geo: GeometryProxy) -> some View {
        let text = PriceFormatter.price(candle.close)
        return CrosshairTag(text: text)
            .position(x: geo.size.width - ChartCrosshair.tagWidth(text) / 2, y: py)
    }

    /// OHLC + volume readout, docked to the top corner away from the cursor.
    private func readout(for candle: Candle, previous: Candle?) -> some View {
        let base = previous?.close ?? candle.open
        let changePercent = base == 0 ? 0 : (candle.close - base) / base * 100
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(readoutDateLabel(for: candle))
                    .foregroundStyle(.secondary)
                Text(PriceFormatter.percent(changePercent))
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.color(for: changePercent))
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 2) {
                GridRow {
                    readoutValue(PulseLocalization.localizedString("chart.open"), PriceFormatter.price(candle.open))
                    readoutValue(PulseLocalization.localizedString("chart.high"), PriceFormatter.price(candle.high))
                }
                GridRow {
                    readoutValue(PulseLocalization.localizedString("chart.low"), PriceFormatter.price(candle.low))
                    readoutValue(PulseLocalization.localizedString("chart.close"), PriceFormatter.price(candle.close))
                }
                if let volume = candle.volume {
                    GridRow {
                        readoutValue(PulseLocalization.localizedString("chart.volume"), PriceFormatter.compact(volume))
                    }
                }
            }
        }
        .font(.system(size: 9).monospacedDigit())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.thickMaterial))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(.separator.opacity(0.5), lineWidth: 0.5))
        .fixedSize()
    }

    private func readoutValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.tertiary)
            Text(value).foregroundStyle(.primary)
        }
    }

    private func readoutDateLabel(for candle: Candle) -> String {
        switch period {
        case .month:
            candle.time.formatted(.dateTime.year().month(.twoDigits))
        default:
            candle.time.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
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
