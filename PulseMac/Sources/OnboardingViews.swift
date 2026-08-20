import SwiftUI
import PulseCore

/// One stop of the onboarding bubble tour: the step's sentence, a position
/// indicator, and the skip/back/next controls. Anchoring is the caller's job;
/// all step motion goes through the shared onboarding state so the tour stays
/// one sequence across hosts.
struct OnboardingTourBubble: View {
    @Environment(AppState.self) private var appState
    let step: OnboardingState.TourStep
    let text: String
    /// Replaces the default advance when moving on needs more than a state bump.
    /// Next always leads somewhere visible: action steps perform the very thing
    /// they point at (open search, open the detail), and the detail page's share
    /// stop navigates back to the list where the pin bubble follows.
    var onAdvance: (() -> Void)?

    private var isLast: Bool { step.next == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 11.5))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                // The epilogue tip carries no position: it is not a step owed.
                if let position = step.numberedPosition {
                    Text("\(position)/\(OnboardingState.TourStep.numberedCount)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if !isLast {
                    Button(PulseLocalization.localizedString("onboarding.tour.skip")) {
                        appState.onboarding.endTour()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                // Only stops whose anchor is still on this page can be returned to.
                if let previous = step.previous, previous.supportsReturn {
                    Button(PulseLocalization.localizedString("onboarding.tour.back")) {
                        appState.onboarding.regressTour()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Button(
                    PulseLocalization.localizedString(isLast ? "onboarding.tour.gotIt" : "onboarding.tour.next")
                ) {
                    if let onAdvance {
                        onAdvance()
                    } else {
                        appState.onboarding.advanceTour()
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(width: 228)
        // Steps move only through their buttons; a stray click outside must not
        // silently end a tour the user never chose to skip.
        .interactiveDismissDisabled()
    }
}
