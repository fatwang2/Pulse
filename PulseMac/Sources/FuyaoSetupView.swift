import SwiftUI
import PulseCore

/// Fuyao detail page, in the same card language as every other provider page: enable
/// switch → shared fact card → an account card carrying the API-key flow. The key goes
/// to the Keychain only after a live validation round-trip; the stored value is never
/// displayed back, only overwritten.
struct FuyaoSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pulseHost) private var host
    @Binding var route: PopoverRoute

    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var connectionError: String?
    /// A configured account hides the input by default; the stored key is never
    /// displayed back, so "edit" simply reveals an empty field that overwrites.
    @State private var showReplaceField = false
    @FocusState private var keyFieldFocused: Bool

    private var configured: Bool { appState.fuyaoConfigured }
    private var enabled: Bool { appState.isProviderEnabled(FuyaoProvider.providerID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // The switch is locked until a key is saved; saving flips it on
                // automatically, disconnecting locks it off again.
                ProviderEnableCard(providerID: FuyaoProvider.providerID, locked: !configured)
                    .padding(.top, 12)
                if configured && enabled {
                    ProviderFactsCard(descriptor: appState.fuyao.descriptor)
                }
                accountCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: showReplaceField) { _, shown in
            if shown { keyFieldFocused = true }
        }
        .animation(.snappy(duration: 0.22), value: showReplaceField)
        .animation(.snappy(duration: 0.25), value: configured)
        .animation(.snappy(duration: 0.25), value: enabled)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) { header }
    }

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: PulseLocalization.localizedString("action.backHelp")) {
                route = .providerList(.accounts)
            }
            Text(PulseLocalization.localizedString("provider.fuyao"))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, host == .pinnedWindow ? 2 : 8)
        .padding(.bottom, 8)
    }

    // MARK: - Account card

    private var accountCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(PulseLocalization.localizedString("fuyao.account"))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Circle()
                    .fill(configured ? Color.green.opacity(0.85) : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(PulseLocalization.localizedString(
                    configured ? "fuyao.status.configured" : "provider.status.notConnected"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().padding(.leading, 12)

            VStack(spacing: 10) {
                if configured {
                    // The saved key is never read back for display, so "edit" is a
                    // reveal: an empty field whose save overwrites the stored key.
                    Button {
                        showReplaceField.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(PulseLocalization.localizedString("fuyao.credentials.replace"))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .rotationEffect(.degrees(showReplaceField ? 180 : 0))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                } else {
                    Text(PulseLocalization.localizedString("fuyao.setup.intro"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !configured || showReplaceField {
                    VStack(spacing: 10) {
                        keyField

                        HStack(alignment: .top) {
                            // The key is signed in the browser; open the management page in place.
                            Button {
                                NSWorkspace.shared.open(URL(string: "https://fuyao.aicubes.cn/admin")!)
                            } label: {
                                Text(PulseLocalization.localizedString("fuyao.setup.getKey"))
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                            Spacer(minLength: 8)
                            Button(PulseLocalization.localizedString(
                                isConnecting ? "fuyao.credentials.validating" : "fuyao.credentials.save"
                            )) {
                                save()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if configured {
                    actionButton(titleKey: "fuyao.disconnect", tint: .red) {
                        appState.clearFuyaoAPIKey()
                        setConnectionError(nil)
                        apiKey = ""
                        showReplaceField = false
                    }
                    .disabled(isConnecting)
                }

                if let connectionError {
                    Text(connectionError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .transition(connectionErrorTransition)
                }
            }
            .padding(12)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Text field in the app's own input idiom: plain field on a quiet surface with a
    /// hairline separator stroke; the stroke picks up the accent on focus.
    private var keyField: some View {
        SecureField("API Key", text: $apiKey)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($keyFieldFocused)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        keyFieldFocused
                            ? AnyShapeStyle(Color.accentColor.opacity(0.6))
                            : AnyShapeStyle(.separator.opacity(0.35)),
                        lineWidth: keyFieldFocused ? 1 : 0.5
                    )
            }
            .animation(.easeOut(duration: 0.15), value: keyFieldFocused)
    }

    /// Full-width action in the app's quiet-surface idiom: tint lives in the text,
    /// feedback lands on mouse-down via `.pressable` — no filled color slabs.
    private func actionButton(titleKey: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(PulseLocalization.localizedString(titleKey))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    private var connectionErrorTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
    }

    @MainActor
    private func setConnectionError(_ message: String?) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.18)) {
            connectionError = message
        }
    }

    // MARK: - Actions

    private func save() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isConnecting = true
        setConnectionError(nil)
        Task {
            do {
                try await appState.saveFuyaoAPIKey(key)
                apiKey = ""
                showReplaceField = false
            } catch {
                setConnectionError(PulseLocalization.localizedString("fuyao.credentials.error"))
            }
            isConnecting = false
        }
    }
}
