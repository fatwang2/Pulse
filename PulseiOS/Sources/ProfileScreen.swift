import SwiftUI
import PulseCore
import PulseUI

/// Full company description, loaded only after the user asks for it. The
/// engine shares the Mac app's daily cache and its distinction between a source
/// with no description and a request that failed.
struct ProfileScreen: View {
    @Environment(IOSAppState.self) private var appState

    let symbol: SymbolID

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
        content
            .navigationTitle(PulseLocalization.localizedString("detail.section.about"))
            .navigationBarTitleDisplayMode(.inline)
            .task(id: Attempt(symbol: symbol, count: retries)) {
                await load()
            }
    }

    private func load() async {
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
            let profile = try await appState.engine.loadProfile(for: symbol)
            guard !Task.isCancelled else { return }
            outcome = profile.map(Outcome.described) ?? .undescribed
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
            ContentUnavailableView {
                Label(
                    PulseLocalization.localizedString("profile.unavailable"),
                    systemImage: "text.page"
                )
            }
        case .failed:
            ContentUnavailableView {
                Label(
                    PulseLocalization.localizedString("profile.loadFailed"),
                    systemImage: "wifi.exclamationmark"
                )
            } actions: {
                Button(PulseLocalization.localizedString("action.retry")) {
                    outcome = .pending
                    retries += 1
                }
                .buttonStyle(.glassProminent)
            }
        case .pending:
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
    }

    private func summary(_ profile: SecurityProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.displayName(for: symbol))
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        MarketBadge(market: symbol.market)
                        Text(symbol.displayCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let classification = profile.classification {
                    Text(classification)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(profile.summary)
                    .font(.body)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}
