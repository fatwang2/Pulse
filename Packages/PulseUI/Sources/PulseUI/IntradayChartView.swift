import SwiftUI
import Charts
import PulseCore

/// Intraday chart: today's trend plus a dashed previous-close baseline; the overall tint follows the price change.
/// The x axis is measured in trading minutes with the lunch break collapsed, so the morning and afternoon
/// sessions each get width proportional to actual trading time — the standard layout for CN/HK minute charts.
/// The domain always spans the full session, so an in-progress day fills in from the left.
public struct IntradayChartView: View {
    let candles: [Candle]
    let previousClose: Double
    let market: Market
    let palette: ChangePalette

    @State private var hovered: Candle?

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
        let session = self.session
        Chart {
            marks(session: session)
        }
        .chartXScale(domain: 0...session.totalMinutes)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xTicks(session: session)) { value in
                if let minute = value.as(Double.self) {
                    // Edge ticks sit on the plot border — a gridline there is just visual noise
                    if minute > 0.5 && minute < session.totalMinutes - 0.5 {
                        AxisGridLine().foregroundStyle(.quaternary)
                    }
                    AxisValueLabel(anchor: tickAnchor(forMinute: minute, session: session)) {
                        Text(tickLabel(forMinute: minute, session: session))
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                crosshairOverlay(proxy: proxy, geo: geo)
            }
        }
        .onChange(of: candles) { _, _ in hovered = nil }
    }

    @ChartContentBuilder
    private func marks(session: IntradayTradingSession) -> some ChartContent {
        ForEach(lineSegments) { segment in
            ForEach(segment.candles, id: \.time) { candle in
                LineMark(
                    x: .value("Time", session.minuteOffset(for: candle.time)),
                    y: .value("Price", candle.close),
                    series: .value("Session", segment.id)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                AreaMark(
                    x: .value("Time", session.minuteOffset(for: candle.time)),
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

    // MARK: - Trading-minute axis

    /// The session frame for the day being displayed (taken from the most recent candle).
    private var trend: IntradayTrendSnapshot {
        IntradayTrendSnapshot(candles: candles, market: market)
    }

    private var session: IntradayTradingSession { trend.session }

    /// Three wall-clock ticks, mainstream-app style (e.g. THS): open at the left edge, close at the
    /// right edge, and the lunch boundary (midday for the US) in between.
    private func xTicks(session: IntradayTradingSession) -> [Double] {
        switch market {
        case .sh, .sz, .hk: [0, session.morningMinutes, session.totalMinutes]
        case .us: [0, 150, session.totalMinutes]  // 150 trading minutes past 9:30 = 12:00
        case .crypto: [0, 720, session.totalMinutes]
        }
    }

    private func tickLabel(forMinute minute: Double, session: IntradayTradingSession) -> String {
        axisTimeFormatter.string(from: session.date(forMinute: minute))
    }

    /// Edge labels anchor inward so they hug the plot borders instead of spilling outside.
    private func tickAnchor(forMinute minute: Double, session: IntradayTradingSession) -> UnitPoint {
        if minute < 0.5 { return .topLeading }
        if minute > session.totalMinutes - 0.5 { return .topTrailing }
        return .top
    }

    /// Candles inside the displayed session (drops the opening auction and any pre/post-market strays).
    private var sessionCandles: [Candle] { trend.candles }

    // MARK: - Crosshair

    @ViewBuilder
    private func crosshairOverlay(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        let session = self.session
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hovered = candle(at: point, proxy: proxy, plot: plot, session: session)
                    case .ended:
                        hovered = nil
                    }
                }
            if let hovered,
               let xPos = proxy.position(forX: session.minuteOffset(for: hovered.time)),
               let yPos = proxy.position(forY: hovered.close) {
                let px = plot.origin.x + xPos
                let py = plot.origin.y + min(max(yPos, 0), plot.height)
                ChartCrosshair.lines(px: px, py: py, in: plot)
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                    .position(x: px, y: py)
                timeTag(for: hovered, px: px, plot: plot, geo: geo)
                priceTag(for: hovered, py: py, geo: geo)
            }
        }
    }

    /// Snap to the candle closest to the cursor's trading-minute position.
    private func candle(at point: CGPoint, proxy: ChartProxy, plot: CGRect, session: IntradayTradingSession) -> Candle? {
        guard plot.insetBy(dx: -2, dy: -2).contains(point),
              let minute: Double = proxy.value(atX: point.x - plot.origin.x) else { return nil }
        return sessionCandles.min {
            abs(session.minuteOffset(for: $0.time) - minute) < abs(session.minuteOffset(for: $1.time) - minute)
        }
    }

    /// Time tag on the x-axis strip, clamped so it never clips at the plot edges.
    private func timeTag(for candle: Candle, px: CGFloat, plot: CGRect, geo: GeometryProxy) -> some View {
        let text = axisTimeFormatter.string(from: candle.time)
        let half = ChartCrosshair.tagWidth(text) / 2
        let x = min(max(px, plot.minX + half), plot.maxX - half)
        return CrosshairTag(text: text)
            .position(x: x, y: min(plot.maxY + 9, geo.size.height - 8))
    }

    /// Price tag over the trailing y-axis strip, vertically centered on the crosshair.
    private func priceTag(for candle: Candle, py: CGFloat, geo: GeometryProxy) -> some View {
        let text = PriceFormatter.price(candle.close)
        return CrosshairTag(text: text)
            .position(x: geo.size.width - ChartCrosshair.tagWidth(text) / 2, y: py)
    }

    // MARK: - Data shaping

    private var yDomain: ClosedRange<Double> {
        let closes = sessionCandles.map(\.close)
        var lo = min(closes.min() ?? previousClose, previousClose)
        var hi = max(closes.max() ?? previousClose, previousClose)
        let pad = max((hi - lo) * 0.1, hi * 0.001)
        lo -= pad
        hi += pad
        return lo...hi
    }

    private var lineSegments: [CandleSegment] {
        let sorted = sessionCandles
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

    private var axisTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        formatter.timeZone = market.timeZone
        return formatter
    }
}

private struct CandleSegment: Identifiable {
    let id: Int
    let candles: [Candle]
}
