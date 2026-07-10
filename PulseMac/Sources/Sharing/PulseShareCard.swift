import SwiftUI
import PulseCore

struct PulseShareCardMetadata {
    let updatedAtText: String
    let slogan: String = "Your market, at a glance."
}

/// Shared brand frame for every present and future Pulse share surface.
struct PulseShareCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let metadata: PulseShareCardMetadata
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)
                .padding(.horizontal, 24)

            content
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)
                .padding(.horizontal, 24)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.06))
                .frame(width: 180, height: 180)
                .blur(radius: 45)
                .offset(x: 60, y: -90)
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Match the lightweight menu-bar brand glyph; the full AppIcon reads as a launcher tile at this size.
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(accentSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Pulse")
                    .font(.system(size: 22, weight: .bold))
                Text(metadata.slogan)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(metadata.updatedAtText)
            Spacer(minLength: 0)
            Text(PulseLocalization.localizedString("share.disclaimer"))
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    private var background: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.08, blue: 0.095)
            : Color(red: 0.975, green: 0.978, blue: 0.985)
    }

    private var accentSurface: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10)
    }

    private var separatorColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
    }
}
