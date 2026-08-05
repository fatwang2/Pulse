import SwiftUI

/// Stand-in for a chart whose data is still on its way: Pulse's own ECG trace,
/// laid into the plot rect, with a highlight running along it the way a monitor
/// sweeps. It holds the chart's frame rather than centering a spinner in the
/// void, so the arriving chart lands in place instead of replacing something
/// unrelated.
public struct ChartLoadingView: View {
    /// Approximates the plot rect the real chart leaves for its trailing price
    /// labels and bottom time labels, so the placeholder sits where the chart will.
    private let axisGutter: CGFloat = 28
    private let labelGutter: CGFloat = 14

    public init() {}

    public var body: some View {
        PulseSweep()
            .padding(.trailing, axisGutter)
            .padding(.bottom, labelGutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The same waiting language as the chart placeholder, for a page that isn't a
/// chart: the trace spans the content's full width so the whole waiting area
/// reads as busy, while its height stays fixed — a waveform stretched to fill a
/// tall page would be a spike, not a heartbeat.
public struct PulseLoadingIndicator: View {
    private let height: CGFloat
    private let inset: CGFloat

    public init(height: CGFloat = 96, inset: CGFloat = 24) {
        self.height = height
        self.inset = inset
    }

    public var body: some View {
        PulseSweep()
            .frame(height: height)
            .padding(.horizontal, inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The waveform, drawn faintly, with a lit segment travelling along it. Loads
/// are usually fast, so what carries the motion is the sweep, not contrast.
struct PulseSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One sweep, at about a resting heart rate.
    private let period: TimeInterval = 1.15
    /// Fraction of the trace lit at any moment.
    private let window: CGFloat = 0.22

    var body: some View {
        ZStack {
            PulseTrace(phase: 0, window: 1)
                .stroke(
                    Color.primary.opacity(0.10),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                )
            if !reduceMotion {
                // A timeline drives the sweep instead of a repeating animation:
                // the view is created and destroyed mid-transition, where a
                // `repeatForever` can come up stalled.
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: period) / period)
                    PulseTrace(phase: phase, window: window)
                        .stroke(
                            Color.primary.opacity(0.38),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
    }
}

/// The app icon's waveform, drawn across the width, with `phase` selecting the
/// stretch of it that is lit. The lit stretch wraps around the end so the sweep
/// runs continuously.
private struct PulseTrace: Shape {
    var phase: CGFloat
    var window: CGFloat

    /// Flat, a small bump, the spike and its recoil, another bump, flat again —
    /// the app icon, laid out left to right. `y` is measured from the top.
    private static let waveform: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.50),
        CGPoint(x: 0.28, y: 0.50),
        CGPoint(x: 0.34, y: 0.40),
        CGPoint(x: 0.39, y: 0.50),
        CGPoint(x: 0.46, y: 0.18),
        CGPoint(x: 0.54, y: 0.84),
        CGPoint(x: 0.60, y: 0.50),
        CGPoint(x: 0.66, y: 0.40),
        CGPoint(x: 0.72, y: 0.50),
        CGPoint(x: 1.00, y: 0.50),
    ]

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let trace = Self.trace(in: rect)
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

    private static func trace(in rect: CGRect) -> Path {
        Path { path in
            let points = waveform.map {
                CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
            }
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }
}
