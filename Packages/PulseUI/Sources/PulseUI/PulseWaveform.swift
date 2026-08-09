import SwiftUI

/// Pulse's canonical waveform geometry, shared by every branded surface.
///
/// The coordinates are the same as the foreground artwork in `AppIcon.icon`.
/// Callers choose the surrounding background and whether the mark is rendered
/// in a context color or with the branded blue live segment.
public struct PulseWaveformMark: View {
    private let primaryColor: Color
    private let liveColor: Color?

    public init(primaryColor: Color = .primary, liveColor: Color? = nil) {
        self.primaryColor = primaryColor
        self.liveColor = liveColor
    }

    public var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let layout = PulseWaveformGeometry.layout(in: rect)

            context.stroke(
                layout.trace,
                with: .color(primaryColor),
                style: StrokeStyle(
                    lineWidth: PulseWaveformGeometry.strokeWidth * layout.scale,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

            if let liveColor {
                context.stroke(
                    layout.liveSegment,
                    with: .color(liveColor),
                    style: StrokeStyle(
                        lineWidth: PulseWaveformGeometry.strokeWidth * layout.scale,
                        lineCap: .butt,
                        lineJoin: .round
                    )
                )
                context.fill(layout.liveEndpoint, with: .color(liveColor))
            }
        }
        .aspectRatio(PulseWaveformGeometry.aspectRatio, contentMode: .fit)
    }
}

/// A trimmable version of the canonical trace used by Pulse's loading sweep.
public struct PulseWaveformTrace: Shape {
    public static let aspectRatio = PulseWaveformGeometry.aspectRatio

    public var phase: CGFloat
    public let window: CGFloat

    public init(phase: CGFloat, window: CGFloat) {
        self.phase = phase
        self.window = window
    }

    public var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let trace = PulseWaveformGeometry.layout(in: rect).trace
        guard window < 1 else { return trace }

        let end = phase
        let start = phase - window
        var lit = Path()
        if start < 0 {
            lit.addPath(trace.trimmedPath(from: 0, to: max(end, 0)))
            lit.addPath(trace.trimmedPath(from: 1 + start, to: 1))
        } else {
            lit.addPath(trace.trimmedPath(from: start, to: min(end, 1)))
        }
        return lit
    }
}

private enum PulseWaveformGeometry {
    static let strokeWidth: CGFloat = 72
    static let liveEndpointRadius: CGFloat = 36

    /// Visual bounds of the canonical centerline plus its 72-point stroke.
    private static let visualBounds = CGRect(x: 134, y: 215, width: 756, height: 580)
    static let aspectRatio = visualBounds.width / visualBounds.height

    struct Layout {
        let trace: Path
        let liveSegment: Path
        let liveEndpoint: Path
        let scale: CGFloat
    }

    static func layout(in rect: CGRect) -> Layout {
        let scale = min(
            rect.width / visualBounds.width,
            rect.height / visualBounds.height
        )
        let offset = CGPoint(
            x: rect.midX - visualBounds.midX * scale,
            y: rect.midY - visualBounds.midY * scale
        )

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: offset.x + x * scale, y: offset.y + y * scale)
        }

        var trace = Path()
        trace.move(to: point(170, 512))
        trace.addLine(to: point(292, 512))
        trace.addCurve(
            to: point(348, 476),
            control1: point(316, 512),
            control2: point(328, 476)
        )
        trace.addCurve(
            to: point(405, 537),
            control1: point(371, 476),
            control2: point(383, 537)
        )
        trace.addCurve(
            to: point(493, 278),
            control1: point(425, 537),
            control2: point(444, 423)
        )
        trace.addCurve(
            to: point(529, 280),
            control1: point(502, 251),
            control2: point(520, 251)
        )
        trace.addLine(to: point(627, 728))
        trace.addCurve(
            to: point(666, 730),
            control1: point(634, 759),
            control2: point(654, 759)
        )
        trace.addLine(to: point(738, 520))
        trace.addCurve(
            to: point(774, 498),
            control1: point(744, 503),
            control2: point(756, 498)
        )
        trace.addLine(to: point(854, 498))

        var liveSegment = Path()
        liveSegment.move(to: point(700, 631))
        liveSegment.addLine(to: point(738, 520))
        liveSegment.addCurve(
            to: point(774, 498),
            control1: point(744, 503),
            control2: point(756, 498)
        )
        liveSegment.addLine(to: point(854, 498))

        let radius = liveEndpointRadius * scale
        let endpoint = point(854, 498)
        let endpointCircle = Path(
            ellipseIn: CGRect(
                x: endpoint.x - radius,
                y: endpoint.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )

        return Layout(
            trace: trace,
            liveSegment: liveSegment,
            liveEndpoint: endpointCircle,
            scale: scale
        )
    }
}
