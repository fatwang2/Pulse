import SwiftUI
import PulseUI

/// Shared brand frame for every present and future Pulse share surface.
/// Content owns its own header; the frame contributes the background ambience and brand footer.
struct PulseShareCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Tints the top ambient glow with the day's direction (up/down palette color).
    /// `nil` falls back to the brand accent.
    let ambientColor: Color?
    @ViewBuilder let content: Content

    init(ambientColor: Color? = nil, @ViewBuilder content: () -> Content) {
        self.ambientColor = ambientColor
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(PulseShareCardStyle.separator(colorScheme))
                .frame(height: 1)
                .padding(.horizontal, 30)

            PulseShareCardFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                stops: colorScheme == .dark
                    ? [
                        .init(color: Color(red: 0.078, green: 0.086, blue: 0.106), location: 0),
                        .init(color: Color(red: 0.063, green: 0.071, blue: 0.094), location: 0.62),
                        .init(color: Color(red: 0.055, green: 0.063, blue: 0.078), location: 1),
                    ]
                    : [
                        .init(color: Color(red: 0.988, green: 0.988, blue: 0.996), location: 0),
                        .init(color: Color(red: 0.965, green: 0.969, blue: 0.980), location: 0.62),
                        .init(color: Color(red: 0.949, green: 0.957, blue: 0.973), location: 1),
                    ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    (ambientColor ?? .accentColor).opacity(colorScheme == .dark ? 0.09 : 0.07),
                    .clear,
                ],
                center: UnitPoint(x: 0.5, y: -0.25),
                startRadius: 0,
                endRadius: 700
            )
        }
    }
}

enum PulseShareCardStyle {
    static func separator(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color(red: 0.1, green: 0.13, blue: 0.18).opacity(0.08)
    }
}

private struct PulseShareCardFooter: View {
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            // Rebuild the launcher mark from the same geometry and exact AppIcon colors.
            PulseWaveformMark(
                primaryColor: Color(red: 0.96863, green: 0.97647, blue: 0.98824),
                liveColor: Color(red: 0.41569, green: 0.69020, blue: 1)
            )
                .frame(width: 28, height: 21.5)
                .accessibilityHidden(true)
                .frame(width: 38, height: 38)
                .background(
                    Color(red: 0.02745, green: 0.09412, blue: 0.18039),
                    in: RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Pulse")
                    .font(.system(size: 15, weight: .bold))
                Text("Your market, at a glance.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text("pulseticker.app")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Color.accentColor.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
        .padding(.horizontal, 30)
        .padding(.top, 14)
        .padding(.bottom, 19)
    }
}
