import SwiftUI
import Charts
import PulseCore

/// Intraday chart: today's trend plus a dashed previous-close baseline; the overall tint follows the price change.
/// The x axis is measured in trading minutes with the lunch break collapsed, so the morning and afternoon
/// sessions each get width proportional to actual trading time — the standard layout for CN/HK minute charts.
/// The domain always spans the full session, so an in-progress day fills in from the left.
/// With `showsExtendedHours` (US only), the pre/post-market sessions attach as compressed gray wings on
/// either side of the regular session, separated by the 9:30 / 16:00 gridlines — the mainstream layout.
///
/// Performance: every derived value (snapshot, segments, y-domain, tint) is computed once per body
/// evaluation and passed down as plain data, and the hover crosshair owns its state in a child view —
/// mouse movement must never re-evaluate the chart marks (up to ~2000 of them on a US extended day).
public struct IntradayChartView: View {
    let candles: [Candle]
    let previousClose: Double
    let market: Market
    let palette: ChangePalette
    let showsExtendedHours: Bool

    public init(candles: [Candle], previousClose: Double, market: Market, palette: ChangePalette,
                showsExtendedHours: Bool = false) {
        self.candles = candles
        self.previousClose = previousClose
        self.market = market
        self.palette = palette
        self.showsExtendedHours = showsExtendedHours
    }

    private static let wingTint = Color.secondary.opacity(0.75)

    public var body: some View {
        let trend = IntradayTrendSnapshot(candles: candles, market: market,
                                          includesExtendedHours: showsExtendedHours)
        let session = trend.session
        let domain = yDomain(for: trend.candles)
        let tint = tint(for: trend)
        let segments = lineSegments(for: trend)
        let formatter = Self.axisFormatter(for: market)

        Chart {
            marks(segments: segments, session: session, tint: tint,
                  domainLower: domain.lowerBound)
        }
        .chartXScale(domain: session.axisLowerBound...session.axisUpperBound)
        .chartYScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: xTicks(session: session)) { value in
                if let minute = value.as(Double.self) {
                    // Edge ticks sit on the plot border — a gridline there is just visual noise
                    if minute > session.axisLowerBound + 0.5 && minute < session.axisUpperBound - 0.5 {
                        AxisGridLine().foregroundStyle(.quaternary)
                    }
                    AxisValueLabel(anchor: tickAnchor(forMinute: minute, session: session)) {
                        Text(tickLabel(forMinute: minute, session: session, formatter: formatter))
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
                IntradayCrosshairOverlay(
                    candles: trend.candles,
                    session: session,
                    tint: tint,
                    wingTint: Self.wingTint,
                    formatter: formatter,
                    proxy: proxy,
                    geo: geo
                )
            }
        }
    }

    @ChartContentBuilder
    private func marks(segments: [CandleSegment], session: IntradayTradingSession,
                       tint: Color, domainLower: Double) -> some ChartContent {
        ForEach(segments) { segment in
            let color = segment.kind == .regular ? tint : Self.wingTint
            ForEach(segment.candles, id: \.time) { candle in
                LineMark(
                    x: .value("Time", session.minuteOffset(for: candle.time)),
                    y: .value("Price", candle.close),
                    series: .value("Series", "price-\(segment.id)")
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                AreaMark(
                    x: .value("Time", session.minuteOffset(for: candle.time)),
                    yStart: .value("Baseline", domainLower),
                    yEnd: .value("Price", candle.close),
                    series: .value("Series", "price-\(segment.id)")
                )
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.02)],
                                                startPoint: .top, endPoint: .bottom))
            }
        }
        RuleMark(y: .value("Prev Close", previousClose))
            .foregroundStyle(.secondary.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
    }

    // MARK: - Trading-minute axis

    /// Three wall-clock ticks, mainstream-app style (e.g. THS): open at the left edge, close at the
    /// right edge, and the lunch boundary (midday for the US) in between. With extended hours the
    /// edges move out to 4:00 / 20:00 and the 9:30 / 16:00 gridlines double as session separators.
    private func xTicks(session: IntradayTradingSession) -> [Double] {
        if session.includesExtendedHours {
            return [session.axisLowerBound, 0, session.totalMinutes, session.axisUpperBound]
        }
        switch market {
        case .sh, .sz, .hk: return [0, session.morningMinutes, session.totalMinutes]
        case .us: return [0, 150, session.totalMinutes]  // 150 trading minutes past 9:30 = 12:00
        case .crypto: return [0, 720, session.totalMinutes]
        }
    }

    /// The compressed wings are too narrow for two time labels each: "4:00" next to "9:30"
    /// (or "16:00" next to "20:00") collides on narrow windows. Name the wings instead —
    /// their exact times are common knowledge and the hover crosshair shows precise values.
    private func tickLabel(forMinute minute: Double, session: IntradayTradingSession,
                           formatter: DateFormatter) -> String {
        if session.includesExtendedHours {
            if minute < session.axisLowerBound + 0.5 {
                return PulseLocalization.localizedString("marketState.preMarket")
            }
            if minute > session.axisUpperBound - 0.5 {
                return PulseLocalization.localizedString("marketState.postMarket")
            }
        }
        return formatter.string(from: session.date(forMinute: minute))
    }

    /// Edge labels anchor inward so they hug the plot borders instead of spilling outside.
    /// In extended mode every label leans away from the narrow wings: the wing names lean
    /// inward from the plot edges and the 9:30 / 16:00 boundary times lean into the wide
    /// regular session — a centered 16:00 would collide with "Post" on narrow windows.
    private func tickAnchor(forMinute minute: Double, session: IntradayTradingSession) -> UnitPoint {
        if session.includesExtendedHours {
            return minute < session.totalMinutes / 2 ? .topLeading : .topTrailing
        }
        if minute < session.axisLowerBound + 0.5 { return .topLeading }
        if minute > session.axisUpperBound - 0.5 { return .topTrailing }
        return .top
    }

    /// DateFormatter construction is expensive; reuse one per market timezone.
    @MainActor private static var formatterCache: [Market: DateFormatter] = [:]

    @MainActor private static func axisFormatter(for market: Market) -> DateFormatter {
        if let cached = formatterCache[market] { return cached }
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        formatter.timeZone = market.timeZone
        formatterCache[market] = formatter
        return formatter
    }

    // MARK: - Data shaping

    /// Day-change tint, anchored on the regular session so a gray post-market wing
    /// doesn't recolor the whole chart after the close.
    private func tint(for trend: IntradayTrendSnapshot) -> Color {
        let session = trend.session
        let reference = trend.candles.last(where: { session.sessionKind(for: $0.time) == .regular })
            ?? trend.candles.last
        guard let reference else { return .secondary }
        return palette.color(for: reference.close - previousClose)
    }

    private func yDomain(for candles: [Candle]) -> ClosedRange<Double> {
        let closes = candles.map(\.close)
        let lo = min(closes.min() ?? previousClose, previousClose)
        let hi = max(closes.max() ?? previousClose, previousClose)
        let pad = max((hi - lo) * 0.1, hi * 0.001)
        return (lo - pad)...(hi + pad)
    }

    /// Gaps are measured in trading minutes: the collapsed lunch break spans ~0 trading
    /// minutes and stays continuous, while genuine data holes still break the line.
    /// Segments also split at session boundaries so the wings render gray; the boundary
    /// candle repeats in both segments to keep the line itself continuous.
    private func lineSegments(for trend: IntradayTrendSnapshot) -> [CandleSegment] {
        let sorted = trend.candles
        let session = trend.session
        guard let first = sorted.first else { return [] }
        let breakMinutes: Double = 20
        var segments: [CandleSegment] = []
        var current = [first]
        var currentKind = session.sessionKind(for: first.time)
        for candle in sorted.dropFirst() {
            let kind = session.sessionKind(for: candle.time)
            let previous = current.last
            let gap = previous.map {
                session.minuteOffset(for: candle.time) - session.minuteOffset(for: $0.time)
            } ?? 0
            if kind != currentKind {
                segments.append(CandleSegment(id: segments.count, kind: currentKind, candles: current))
                current = (gap <= breakMinutes ? previous.map { [$0] } ?? [] : []) + [candle]
                currentKind = kind
            } else if gap > breakMinutes {
                segments.append(CandleSegment(id: segments.count, kind: currentKind, candles: current))
                current = [candle]
            } else {
                current.append(candle)
            }
        }
        segments.append(CandleSegment(id: segments.count, kind: currentKind, candles: current))
        return segments
    }
}

private struct CandleSegment: Identifiable {
    let id: Int
    let kind: IntradaySessionKind
    let candles: [Candle]
}

/// Hover crosshair as its own view so `hovered` state changes re-render only these few
/// shapes and tags, never the chart marks behind them.
private struct IntradayCrosshairOverlay: View {
    let candles: [Candle]
    let session: IntradayTradingSession
    let tint: Color
    let wingTint: Color
    let formatter: DateFormatter
    let proxy: ChartProxy
    let geo: GeometryProxy

    @State private var hovered: Candle?

    var body: some View {
        let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hovered = candle(at: point, plot: plot)
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
                    .fill(session.sessionKind(for: hovered.time) == .regular ? tint : wingTint)
                    .frame(width: 5, height: 5)
                    .position(x: px, y: py)
                timeTag(for: hovered, px: px, plot: plot)
                priceTag(for: hovered, py: py)
            }
        }
        .onChange(of: candles) { _, _ in hovered = nil }
    }

    /// Snap to the candle closest to the cursor's trading-minute position.
    private func candle(at point: CGPoint, plot: CGRect) -> Candle? {
        guard plot.insetBy(dx: -2, dy: -2).contains(point),
              let minute: Double = proxy.value(atX: point.x - plot.origin.x) else { return nil }
        return candles.min {
            abs(session.minuteOffset(for: $0.time) - minute) < abs(session.minuteOffset(for: $1.time) - minute)
        }
    }

    /// Time tag on the x-axis strip, clamped so it never clips at the plot edges.
    private func timeTag(for candle: Candle, px: CGFloat, plot: CGRect) -> some View {
        let text = formatter.string(from: candle.time)
        let half = ChartCrosshair.tagWidth(text) / 2
        let x = min(max(px, plot.minX + half), plot.maxX - half)
        return CrosshairTag(text: text)
            .position(x: x, y: min(plot.maxY + 9, geo.size.height - 8))
    }

    /// Price tag over the trailing y-axis strip, vertically centered on the crosshair.
    private func priceTag(for candle: Candle, py: CGFloat) -> some View {
        let text = PriceFormatter.price(candle.close)
        return CrosshairTag(text: text)
            .position(x: geo.size.width - ChartCrosshair.tagWidth(text) / 2, y: py)
    }
}
