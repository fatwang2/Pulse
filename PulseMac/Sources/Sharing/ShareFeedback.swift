import SwiftUI
import PulseCore

struct ShareFeedback: Equatable {
    let id = UUID()
    let isSuccess: Bool
}

/// Shared transient confirmation for every copy-to-clipboard share action.
struct ShareFeedbackHUD: View {
    let feedback: ShareFeedback

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(feedback.isSuccess ? .green : .orange)
            Text(PulseLocalization.localizedString(
                feedback.isSuccess ? "share.copySuccess" : "share.copyFailed"
            ))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .medium))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .fixedSize(horizontal: true, vertical: false)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 0.5)
        }
        .accessibilityLabel(PulseLocalization.localizedString(
            feedback.isSuccess ? "share.copySuccess" : "share.copyFailed"
        ))
    }
}
