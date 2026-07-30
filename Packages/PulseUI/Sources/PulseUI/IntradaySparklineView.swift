import SwiftUI
import PulseCore

/// Lightweight Canvas rendering of the same canonical trading-session geometry used by
/// `IntradayChartView`. It is suitable for dense list rows and off-screen share images.
///
/// With `includesExtendedHours` (US only) the pre/post-market wings render in the same
/// muted gray as the detail chart, separated by hairlines at the 9:30 / 16:00 boundaries —
/// without an x-axis those two cues are all that distinguishes the sessions.
public struct IntradaySparklineView: View {
    let candles: [Candle]
    let previousClose: Double?
    let market: Market
    let tint: Color
    let includesExtendedHours: Bool

    public init(
        candles: [Candle],
        previousClose: Double? = nil,
        market: Market,
        tint: Color,
        includesExtendedHours: Bool = false
    ) {
        self.candles = candles
        self.previousClose = previousClose
        self.market = market
        self.tint = tint
        self.includesExtendedHours = includesExtendedHours
    }

    private static let wingTint = Color.secondary.opacity(0.75)

    public var body: some View {
        let trend = IntradayTrendSnapshot(
            candles: candles,
            market: market,
            includesExtendedHours: includesExtendedHours
        )
        Canvas { context, size in
            guard trend.candles.count > 1 else { return }
            let session = trend.session
            let domain = yDomain(for: trend.candles)
            let axisSpan = session.axisUpperBound - session.axisLowerBound

            func xPosition(forMinute minute: Double) -> CGFloat {
                size.width * CGFloat((minute - session.axisLowerBound) / axisSpan)
            }

            func point(for candle: Candle) -> CGPoint {
                let x = xPosition(forMinute: session.minuteOffset(for: candle.time))
                let y = 1 - (candle.close - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
                return CGPoint(x: x, y: size.height * CGFloat(y))
            }

            // Session separators on the 9:30 / 16:00 boundaries, standing in for the
            // detail chart's boundary gridlines.
            if session.includesExtendedHours {
                for minute in [0, session.totalMinutes] {
                    let x = xPosition(forMinute: minute)
                    var rule = Path()
                    rule.move(to: CGPoint(x: x, y: 0))
                    rule.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(
                        rule,
                        with: .color(.secondary.opacity(0.18)),
                        style: StrokeStyle(lineWidth: 0.5)
                    )
                }
            }

            for segment in lineSegments(trend.candles, session: session) {
                let color = segment.kind == .regular ? tint : Self.wingTint
                var line = Path()
                line.move(to: point(for: segment.candles[0]))
                for candle in segment.candles.dropFirst() {
                    line.addLine(to: point(for: candle))
                }

                var area = line
                area.addLine(to: CGPoint(x: point(for: segment.candles.last!).x, y: size.height))
                area.addLine(to: CGPoint(x: point(for: segment.candles[0]).x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.16), color.opacity(0.01)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
                context.stroke(
                    line,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                )
            }

            if let previousClose {
                let normalizedY = 1 - (previousClose - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
                let y = size.height * CGFloat(normalizedY)
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y))
                rule.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    rule,
                    with: .color(.secondary.opacity(0.35)),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 2])
                )
            }
        }
    }

    private func yDomain(for candles: [Candle]) -> ClosedRange<Double> {
        let closes = candles.map(\.close)
        let baseline = previousClose ?? closes.first ?? 0
        var lo = min(closes.min() ?? baseline, baseline)
        var hi = max(closes.max() ?? baseline, baseline)
        let pad = max((hi - lo) * 0.1, hi * 0.001, 0.0001)
        lo -= pad
        hi += pad
        return lo...hi
    }

    private struct Segment {
        let kind: IntradaySessionKind
        let candles: [Candle]
    }

    /// Gaps are measured in trading minutes: the collapsed lunch break spans ~0 trading
    /// minutes and stays continuous, while genuine data holes still break the line.
    /// Segments also split at session boundaries so the wings render gray; the boundary
    /// candle repeats in both segments to keep the line itself continuous.
    private func lineSegments(_ candles: [Candle], session: IntradayTradingSession) -> [Segment] {
        guard let first = candles.first else { return [] }
        let breakMinutes: Double = 20
        var segments: [Segment] = []
        var current = [first]
        var currentKind = session.sessionKind(for: first.time)
        for candle in candles.dropFirst() {
            let kind = session.sessionKind(for: candle.time)
            let previous = current.last
            let gap = previous.map {
                session.minuteOffset(for: candle.time) - session.minuteOffset(for: $0.time)
            } ?? 0
            if kind != currentKind {
                segments.append(Segment(kind: currentKind, candles: current))
                current = (gap <= breakMinutes ? previous.map { [$0] } ?? [] : []) + [candle]
                currentKind = kind
            } else if gap > breakMinutes {
                segments.append(Segment(kind: currentKind, candles: current))
                current = [candle]
            } else {
                current.append(candle)
            }
        }
        segments.append(Segment(kind: currentKind, candles: current))
        return segments
    }
}
