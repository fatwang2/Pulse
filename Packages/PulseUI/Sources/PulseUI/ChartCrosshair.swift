import SwiftUI

/// Shared pieces for the hover crosshair on quote charts.
enum ChartCrosshair {
    /// Vertical + horizontal locator lines through (px, py), clipped to the plot rect.
    /// Pass `py: nil` to draw the vertical line only (e.g. the volume pane).
    static func lines(px: CGFloat, py: CGFloat?, in plot: CGRect) -> some View {
        Path { path in
            path.move(to: CGPoint(x: px, y: plot.minY))
            path.addLine(to: CGPoint(x: px, y: plot.maxY))
            if let py {
                path.move(to: CGPoint(x: plot.minX, y: py))
                path.addLine(to: CGPoint(x: plot.maxX, y: py))
            }
        }
        .stroke(.secondary.opacity(0.5), lineWidth: 0.8)
    }

    /// Rough width of a tag capsule; caption2 monospaced digits are ~6pt per character.
    static func tagWidth(_ text: String) -> CGFloat {
        CGFloat(text.count) * 6 + 12
    }
}

/// Small solid-backed label that marks the crosshair position on an axis.
struct CrosshairTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.thickMaterial))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(.separator.opacity(0.5), lineWidth: 0.5))
    }
}
