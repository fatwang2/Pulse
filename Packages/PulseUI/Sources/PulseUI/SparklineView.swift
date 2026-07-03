import SwiftUI

/// Mini trend line for list rows. `values` is the day's intraday close series; `baseline` is the previous close.
/// Drawn directly with Canvas instead of Swift Charts: one chart instance per row is too costly when the whole list refreshes.
public struct SparklineView: View {
    let values: [Double]
    let baseline: Double?
    let tint: Color

    public init(values: [Double], baseline: Double? = nil, tint: Color) {
        self.values = values
        self.baseline = baseline
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }

            var lo = values.min() ?? 0
            var hi = values.max() ?? 1
            if let baseline {
                lo = min(lo, baseline)
                hi = max(hi, baseline)
            }
            let pad = max((hi - lo) * 0.08, hi * 0.0005, 0.0001)
            lo -= pad
            hi += pad
            let span = hi - lo

            func point(_ index: Int) -> CGPoint {
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height * CGFloat(1 - (values[index] - lo) / span)
                )
            }

            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count {
                line.addLine(to: point(i))
            }

            // Gradient fill under the line
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.16), tint.opacity(0.01)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            ))

            // Dashed baseline at previous close
            if let baseline {
                let y = size.height * CGFloat(1 - (baseline - lo) / span)
                var rule = Path()
                rule.move(to: CGPoint(x: 0, y: y))
                rule.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(rule, with: .color(.secondary.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            }

            context.stroke(line, with: .color(tint),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }
}
