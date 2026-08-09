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
            PulseWaveformTrace(phase: 0, window: 1)
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
                    PulseWaveformTrace(phase: phase, window: window)
                        .stroke(
                            Color.primary.opacity(0.38),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .aspectRatio(PulseWaveformTrace.aspectRatio, contentMode: .fit)
    }
}
