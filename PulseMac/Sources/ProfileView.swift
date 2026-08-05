import SwiftUI
import PulseCore
import PulseUI

/// What a symbol actually is. Opened from the detail page's corner link, and it
/// is this page — not that link — that goes and asks: a summary nobody opened
/// is a request nobody needed.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    let symbol: SymbolID
    @Binding var route: PopoverRoute

    /// What the last attempt came back with. Nothing found and nothing reached
    /// are different outcomes: only the second one is worth retrying.
    private enum Outcome {
        case pending
        case described(SecurityProfile)
        case undescribed
        case failed
    }

    private struct Attempt: Hashable {
        var symbol: SymbolID
        var count: Int
    }

    @State private var outcome: Outcome = .pending
    @State private var isLoading = false
    @State private var retries = 0

    var body: some View {
        VStack(spacing: 0) {
            PositionPageHeader(
                symbol: symbol,
                title: nil,
                onBack: { route = .detail(symbol) }
            )
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: Attempt(symbol: symbol, count: retries)) {
            await load()
        }
    }

    private func load() async {
        // Cached for the day, so coming back is instant; the loader waits that
        // case out rather than flashing through it.
        let loaderDelay = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            isLoading = true
        }
        defer {
            loaderDelay.cancel()
            isLoading = false
        }
        do {
            let loaded = try await appState.engine.loadProfile(for: symbol)
            guard !Task.isCancelled else { return }
            outcome = loaded.map(Outcome.described) ?? .undescribed
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            outcome = .failed
        }
    }

    @ViewBuilder
    private var content: some View {
        switch outcome {
        case .described(let profile):
            summary(profile)
        case .undescribed:
            // The source carries this symbol's prices but has nothing written
            // about it — common outside the large caps.
            ContentUnavailableView {
                Label(
                    PulseLocalization.localizedString("profile.unavailable"),
                    systemImage: "text.page"
                )
            }
            .frame(maxHeight: .infinity)
        case .failed:
            failure
        case .pending:
            if isLoading {
                PulseLoadingIndicator()
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private func summary(_ profile: SecurityProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let classification = profile.classification {
                    Text(classification)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(profile.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    /// Nothing was reached, which is not the same as nothing being there — so
    /// this offers to ask again rather than reporting an absence.
    private var failure: some View {
        VStack(spacing: 10) {
            Text(PulseLocalization.localizedString("profile.loadFailed"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(PulseLocalization.localizedString("action.retry")) {
                outcome = .pending
                retries += 1
            }
            .buttonStyle(.pressable)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tint)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
