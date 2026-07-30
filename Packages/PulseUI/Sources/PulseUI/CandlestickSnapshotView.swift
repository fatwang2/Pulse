import SwiftUI
import PulseCore

/// Static Canvas twin of `CandlestickChartView` for off-screen share cards: the same
/// body/wick/volume-band geometry and extended-session tinting, with no axes and no
/// interaction. Callers pass exactly the candles to show (e.g. the detail chart's
/// visible zoom window), so what lands on the card is what was on screen.
public struct CandlestickSnapshotView: View {
    let candles: [Candle]
    let palette: ChangePalette
    let highlightsExtendedHours: Bool

    public init(
        candles: [Candle],
        palette: ChangePalette,
        highlightsExtendedHours: Bool = false
    ) {
        self.candles = candles
        self.palette = palette
        self.highlightsExtendedHours = highlightsExtendedHours
    }

    /// Fraction of the y-domain the in-pane volume band occupies; mirrors
    /// `CandlestickChartView.volumeBandFraction` and its 28% price-domain reserve.
    private static let volumeBandFraction = 0.20

    public var body: some View {
        Canvas { context, size in
            guard !candles.isEmpty else { return }
            let lo = candles.map(\.low).min() ?? 0
            let hi = candles.map(\.high).max() ?? 1
            let maxVolume = candles.compactMap(\.volume).max() ?? 0
            let span = max(hi - lo, hi * 0.001, 0.0001)
            let bottomPad = maxVolume > 0 ? span * 0.28 : span * 0.05
            let domainLo = lo - bottomPad
            let domainSpan = (hi + span * 0.05) - domainLo

            let slot = size.width / CGFloat(candles.count)
            let bodyWidth = min(max(slot * 0.62, 1), 24)

            func y(_ price: Double) -> CGFloat {
                size.height * CGFloat(1 - (price - domainLo) / domainSpan)
            }

            if highlightsExtendedHours {
                for (index, candle) in candles.enumerated() {
                    let kind = IntradayTradingSession.usSessionKind(for: candle.time)
                    guard kind != .regular else { continue }
                    context.fill(
                        Path(CGRect(x: slot * CGFloat(index), y: 0, width: slot, height: size.height)),
                        with: .color(kind == .pre ? Color.blue.opacity(0.045) : Color.purple.opacity(0.04))
                    )
                }
            }

            let minBody = domainSpan * 0.002
            for (index, candle) in candles.enumerated() {
                let color = palette.color(isUp: candle.isUp)
                let centerX = slot * (CGFloat(index) + 0.5)

                if maxVolume > 0, let volume = candle.volume {
                    let top = domainLo + domainSpan * Self.volumeBandFraction * volume / maxVolume
                    context.fill(
                        Path(CGRect(x: centerX - bodyWidth / 2, y: y(top),
                                    width: bodyWidth, height: size.height - y(top))),
                        with: .color(color.opacity(0.35))
                    )
                }

                var wick = Path()
                wick.move(to: CGPoint(x: centerX, y: y(candle.low)))
                wick.addLine(to: CGPoint(x: centerX, y: y(candle.high)))
                context.stroke(wick, with: .color(color), style: StrokeStyle(lineWidth: 1))

                // Doji candles (open == close) still need a visible body.
                let bodyLow = min(candle.open, candle.close)
                var bodyHigh = max(candle.open, candle.close)
                if bodyHigh - bodyLow < minBody { bodyHigh = bodyLow + minBody }
                context.fill(
                    Path(CGRect(x: centerX - bodyWidth / 2, y: y(bodyHigh),
                                width: bodyWidth, height: y(bodyLow) - y(bodyHigh))),
                    with: .color(color)
                )
            }
        }
    }
}
