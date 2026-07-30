import SwiftUI
import PulseCore

/// Lightweight Canvas rendering of the same canonical trading-session geometry used by
/// `IntradayChartView`. It is suitable for dense list rows and off-screen share images.
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

    public var body: some View {
        let trend = IntradayTrendSnapshot(
            candles: candles,
            market: market,
            includesExtendedHours: includesExtendedHours
        )
        Canvas { context, size in
            guard trend.candles.count > 1 else { return }
            let domain = yDomain(for: trend.candles)
            let axisSpan = trend.session.axisUpperBound - trend.session.axisLowerBound

            func point(for candle: Candle) -> CGPoint {
                let offset = trend.session.minuteOffset(for: candle.time)
                let x = (offset - trend.session.axisLowerBound) / axisSpan
                let y = 1 - (candle.close - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
                return CGPoint(x: size.width * CGFloat(x), y: size.height * CGFloat(y))
            }

            for segment in lineSegments(trend.candles, session: trend.session) {
                var line = Path()
                line.move(to: point(for: segment[0]))
                for candle in segment.dropFirst() {
                    line.addLine(to: point(for: candle))
                }

                var area = line
                area.addLine(to: CGPoint(x: point(for: segment.last!).x, y: size.height))
                area.addLine(to: CGPoint(x: point(for: segment[0]).x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.16), tint.opacity(0.01)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
                context.stroke(
                    line,
                    with: .color(tint),
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

    /// Gaps are measured in trading minutes: the collapsed lunch break spans ~0 trading
    /// minutes and stays continuous, while genuine data holes still break the line.
    private func lineSegments(_ candles: [Candle], session: IntradayTradingSession) -> [[Candle]] {
        guard let first = candles.first else { return [] }
        let breakMinutes: Double = 20
        var segments: [[Candle]] = []
        var current = [first]
        for candle in candles.dropFirst() {
            if let previous = current.last,
               session.minuteOffset(for: candle.time) - session.minuteOffset(for: previous.time) > breakMinutes {
                segments.append(current)
                current = [candle]
            } else {
                current.append(candle)
            }
        }
        segments.append(current)
        return segments
    }
}
